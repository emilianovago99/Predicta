#!/usr/bin/env bash
set -euo pipefail
umask 077
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo 'Usage: bash scripts/restore_db.sh /absolute/path/backup.sql.gz' >&2
  exit 2
fi
backup=$(realpath -- "$1")
gzip -t "$backup"
cd "$(dirname "$0")/.."
compose=(docker compose --env-file "${ENV_FILE:-.env.production}" -f "${COMPOSE_FILE:-docker-compose.prod.yml}")
printf 'This replaces tables in the configured database. File: %s\nType RESTORE to continue: ' "$backup"
read -r confirmation
[[ "$confirmation" == RESTORE ]] || { echo 'Cancelled'; exit 1; }
# Stop application writers; an unsuccessful restore leaves them stopped for inspection.
"${compose[@]}" stop api web
gzip -dc "$backup" | "${compose[@]}" exec -T mariadb sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb --user="$MARIADB_USER" "$MARIADB_DATABASE"'
echo 'Restore complete. Review the database, then start services with docker compose up -d.'
