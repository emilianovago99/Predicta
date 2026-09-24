#!/usr/bin/env bash
# Update an existing Oracle installation. Run with sudo; secrets stay on the VM.
set -Eeuo pipefail
umask 077

usage() {
  cat <<'HELP'
Usage: sudo bash /opt/predicta/current/scripts/update_oracle.sh [--check]

Downloads origin/main, builds a release, backs up the database and checks HTTPS.
--check only fetches main and reports the installed/available revisions.
Requires an existing /opt/predicta/current production installation.
Advanced: PREDICTA_ROOT and PREDICTA_REPO override /opt/predicta and /root/Predicta.
HELP
}
check=false
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --check) check=true ;;
  '') ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }
for command in git docker curl python3 flock tar realpath; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

app=$(realpath -e -- "${PREDICTA_ROOT:-/opt/predicta}")
repo=$(realpath -e -- "${PREDICTA_REPO:-/root/Predicta}")
exec 9>"$app/update.lock"
flock -n 9 || { echo 'Another update is running.' >&2; exit 1; }
[[ -L "$app/current" ]] || { echo 'An existing current symlink is required.' >&2; exit 1; }
current=$(realpath -e -- "$app/current")
case "$current" in
  "$app/releases/"*) ;;
  *) echo 'current must point inside the releases directory.' >&2; exit 1 ;;
esac
[[ -s "$current/.env.production" ]] || { echo 'Missing production environment.' >&2; exit 1; }

export GIT_TERMINAL_PROMPT=0
git -C "$repo" fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
revision=$(git -C "$repo" rev-parse --verify 'refs/remotes/origin/main^{commit}')
[[ "$revision" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid main revision.' >&2; exit 1; }
printf 'Installed: %s\nAvailable main: %s\n' "$(basename "$current")" "$revision"
if "$check"; then
  echo 'Check complete. No containers, database or production configuration changed.'
  exit 0
fi

mkdir -p "$app/releases" "$app/backups" "$app/deployments"
log="$app/deployments/$(date -u +%Y%m%dT%H%M%SZ)-${revision:0:12}-$$.log"
exec > >(tee -a "$log") 2>&1
phase=prepare
stage=''
on_exit() {
  local result=$1
  if [[ -n "$stage" && "$stage" == "$app/releases/.staging."* ]]; then
    rm -rf -- "$stage"
  fi
  if (( result != 0 )); then
    printf '\nUPDATE FAILED during %s. Log: %s\n' "$phase" "$log" >&2
    printf 'current still points to: %s\n' "$(readlink -f "$app/current")" >&2
    if [[ "$phase" == start || "$phase" == health || "$phase" == activate ]]; then
      echo 'Containers or schema may already have changed. Inspect before retrying.' >&2
      echo 'No automatic database restore or application rollback was performed.' >&2
    fi
  fi
}
trap 'on_exit $?' EXIT

compose() {
  docker compose --project-name predicta --project-directory "$release" \
    --env-file "$release/.env.production" -f "$release/docker-compose.prod.yml" "$@"
}
health() {
  local domain
  # Parse resolved configuration in memory; never print interpolated secrets.
  domain=$(compose config --format json | python3 -c '
import json, re, sys
domain = json.load(sys.stdin)["services"]["caddy"]["environment"]["DOMAIN"]
if not re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?", domain):
    raise SystemExit("Invalid production DOMAIN")
print(domain)
')
  curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
    --retry 8 --retry-delay 3 --retry-connrefused "https://$domain/api/health" |
    python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(0 if data.get("status")=="ok" and data.get("database")=="ok" else 1)'
  printf 'HTTPS and database OK: https://%s\n' "$domain"
}

release="$app/releases/$revision"
if [[ "$release" == "$current" ]]; then
  phase=health
  health
  echo 'Already running this main revision. No rebuild required.'
  exit 0
fi

if [[ ! -e "$release" ]]; then
  stage=$(mktemp -d "$app/releases/.staging.XXXXXXXX")
  git -C "$repo" archive "$revision" | tar -x -C "$stage"
  printf '%s\n' "$revision" > "$stage/.release-commit"
  mv -- "$stage" "$release"
  stage=''
else
  # Permit a retry of a complete release prepared by this updater.
  [[ ! -L "$release" && -f "$release/.release-commit" && "$(cat "$release/.release-commit")" == "$revision" ]] || {
    echo "Unrecognized existing release: $release; inspect it manually." >&2; exit 1;
  }
fi
cp -- "$current/.env.production" "$release/.env.production"
chmod 600 "$release/.env.production"
compose config --quiet

phase=build
echo 'Building main while the current containers continue running...'
compose build api web

phase=backup
echo 'Creating the pre-migration database backup...'
# exec -T must not consume the SSH/script input stream.
BACKUP_DIR="$app/backups" ENV_FILE=.env.production COMPOSE_FILE=docker-compose.prod.yml \
  bash "$current/scripts/backup_db.sh" </dev/null

phase=start
echo 'Updating containers; a brief service interruption is expected.'
compose up -d --wait --wait-timeout 300
phase=health
health

phase=activate
ln -sfnT -- "$current" "$app/previous"
ln -s -- "$release" "$app/.current.$$"
mv -Tf -- "$app/.current.$$" "$app/current"
phase=complete
printf '\nDeployment complete: %s\nPrevious release: %s\nLog: %s\n' "$revision" "$current" "$log"
compose ps
