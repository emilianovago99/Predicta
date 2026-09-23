#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
compose=(docker compose --env-file "${ENV_FILE:-.env.production}" -f "${COMPOSE_FILE:-docker-compose.prod.yml}")
backup_dir=${BACKUP_DIR:-backups}
mkdir -p "$backup_dir"
target="$backup_dir/predicta-$(date -u +%Y%m%dT%H%M%SZ)-$$.sql.gz"
tmp="${target}.partial"
trap 'rm -f -- "$tmp"' EXIT
"${compose[@]}" exec -T mariadb sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb-dump --user="$MARIADB_USER" --single-transaction --quick --skip-lock-tables --hex-blob --default-character-set=utf8mb4 "$MARIADB_DATABASE"' | gzip > "$tmp"
gzip -t "$tmp"
mv -- "$tmp" "$target"
printf 'Backup: %s\n' "$target"
