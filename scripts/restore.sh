#!/usr/bin/env bash

# Restore core services backups (vault, traefik certs/logs, logto data and DB)

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
RESTORE_DATE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --date|-d)
      RESTORE_DATE="$2"; shift 2;;
    --dry-run)
      DRY_RUN=true; shift;;
    --list|-l)
      echo "Available backups:"; ls -1 "$BACKUP_DIR" || true; exit 0;;
    --help|-h)
      echo "Usage: $0 [--date YYYYMMDD_HHMMSS] [--dry-run]"; exit 0;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [ -z "$RESTORE_DATE" ]; then
  echo "Finding latest backup in $BACKUP_DIR"
  RESTORE_DATE=$(ls -1 "$BACKUP_DIR" | sort -r | head -n1 | sed -E 's/.*_([0-9_]+)\.tar\.gz$/\1/' || true)
fi

echo "Restore date: $RESTORE_DATE"

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: no changes will be made"
fi

# Restore Vault data
if [ -f "$BACKUP_DIR/vault_data_${RESTORE_DATE}.tar.gz" ]; then
  echo "Restoring vault_data..."
  if [ "$DRY_RUN" = false ]; then
    docker volume rm vault_data 2>/dev/null || true
    docker volume create vault_data
    docker run --rm -v vault_data:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar xzf /backup/vault_data_${RESTORE_DATE}.tar.gz"
  fi
else
  echo "No vault backup found for date: $RESTORE_DATE"
fi

# Restore Traefik certs/logs
for v in traefik_certs traefik_logs; do
  if [ -f "$BACKUP_DIR/${v}_${RESTORE_DATE}.tar.gz" ]; then
    echo "Restoring ${v}..."
    if [ "$DRY_RUN" = false ]; then
      docker volume rm ${v} 2>/dev/null || true
      docker volume create ${v}
      docker run --rm -v ${v}:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar xzf /backup/${v}_${RESTORE_DATE}.tar.gz"
    fi
  else
    echo "No backup for ${v} on date: $RESTORE_DATE"
  fi
done

# Restore Logto data
if [ -f "$BACKUP_DIR/logto_data_${RESTORE_DATE}.tar.gz" ]; then
  echo "Restoring logto_data..."
  if [ "$DRY_RUN" = false ]; then
    docker volume rm logto_data 2>/dev/null || true
    docker volume create logto_data
    docker run --rm -v logto_data:/data -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar xzf /backup/logto_data_${RESTORE_DATE}.tar.gz"
  fi
fi

# Restore logto-db
if [ -f "$BACKUP_DIR/logto_db_${RESTORE_DATE}.sql.gz" ]; then
  echo "Restoring logto-db..."
  if [ "$DRY_RUN" = false ]; then
    docker-compose up -d logto-db
    gunzip -c "$BACKUP_DIR/logto_db_${RESTORE_DATE}.sql.gz" | docker exec -i logto-db psql -U "$LOGTO_DB_USER" -d "$LOGTO_DB_NAME"
  fi
fi

echo "Restore complete. Start core services with: ./scripts/start.sh"
