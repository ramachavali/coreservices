#!/usr/bin/env bash

# Backup core services: vault, traefik certs/logs, logto DB and data

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
fi

LOGTO_DB_USER="${LOGTO_DB_USER:-logto}"
LOGTO_DB_PASSWORD="${LOGTO_DB_PASSWORD:-}"
LOGTO_DB_NAME="${LOGTO_DB_NAME:-logto_db}"

if [ -z "$LOGTO_DB_PASSWORD" ]; then
  echo "❌ LOGTO_DB_PASSWORD is not set."
  echo "Run ./scripts/setup.sh to render secrets, or set LOGTO_DB_PASSWORD in .rendered.env/.env"
  exit 1
fi

BACKUP_DIR="${BACKUP_LOCATION:-$HOME/coreservices-backups}"
DATE=$(date +%Y%m%d_%H%M%S)
COMPRESS=true

mkdir -p "$BACKUP_DIR"

echo "💾 Core services backup -> $BACKUP_DIR"

# 1) Backup Vault data (volume)
echo "  - Backing up Vault data (vault_data)..."
if docker volume inspect vault_data >/dev/null 2>&1; then
  docker run --rm -v vault_data:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar czf /backup/vault_data_${DATE}.tar.gz ." || {
    echo "    ⚠️ Failed to archive vault_data volume"
  }
else
  echo "    ⚠️ vault_data volume not found"
fi

# 2) Backup Traefik certs and logs
echo "  - Backing up Traefik certs and logs..."
docker run --rm -v traefik_certs:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar czf /backup/traefik_certs_${DATE}.tar.gz ." 2>/dev/null || true
docker run --rm -v traefik_logs:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar czf /backup/traefik_logs_${DATE}.tar.gz ." 2>/dev/null || true

# 3) Backup Logto files (volume)
echo "  - Backing up Logto data (logto_data)..."
docker run --rm -v logto_data:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar czf /backup/logto_data_${DATE}.tar.gz ." 2>/dev/null || true

# 4) Dump logto-db (Postgres)
echo "  - Dumping logto-db (Postgres)..."
if docker-compose ps --services --filter "status=running" | grep -q "logto-db"; then
  docker exec logto-db pg_dump -U "$LOGTO_DB_USER" "$LOGTO_DB_NAME" | gzip > "$BACKUP_DIR/logto_db_${DATE}.sql.gz" || true
else
  echo "    ⚠️ logto-db not running; skipping DB dump"
fi

echo "Backup complete. Files in: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | sed -n '1,100p'
