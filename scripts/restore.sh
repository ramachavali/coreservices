#!/usr/bin/env bash

# Restore core services backups (vault, traefik certs/logs, logto data and DB)

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

COMPOSE_CMD=(docker-compose)

compose_volume_list() {
  local compose_volumes=()
  while IFS= read -r vol; do
    [ -n "$vol" ] && compose_volumes+=("$vol")
  done < <("${COMPOSE_CMD[@]}" config --volumes)
  printf '%s\n' "${compose_volumes[@]}"
}

compose_service_exists() {
  local target="$1"
  compose_services=()
  while IFS= read -r svc; do
    compose_services+=("$svc")
  done < <("${COMPOSE_CMD[@]}" config --services)
  for svc in "${compose_services[@]}"; do
    if [ "$svc" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

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
  RESTORE_DATE=$(ls -1 "$BACKUP_DIR" 2>/dev/null | grep -Eo '[0-9]{8}_[0-9]{6}' | sort -ur | head -n1 || true)
fi

echo "Restore date: $RESTORE_DATE"

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: no changes will be made"
fi

# Restore all named compose volumes
echo "Restoring named volumes from compose..."
volumes=()
while IFS= read -r v; do
  [ -n "$v" ] && volumes+=("$v")
done < <(compose_volume_list)

for volume in "${volumes[@]}"; do
  archive="$BACKUP_DIR/${volume}_${RESTORE_DATE}.tar.gz"
  if [ -f "$archive" ]; then
    echo "Restoring ${volume}..."
    if [ "$DRY_RUN" = false ]; then
      docker volume rm "$volume" 2>/dev/null || true
      docker volume create "$volume"
      docker run --rm -v "$volume:/data" -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar xzf /backup/$(basename "$archive")"
    fi
  else
    echo "No backup for ${volume} on date: $RESTORE_DATE"
  fi
done

# Restore logto-db
if [ -f "$BACKUP_DIR/logto_db_${RESTORE_DATE}.sql.gz" ]; then
  echo "Restoring logto-db..."
  if [ "$DRY_RUN" = false ]; then
    if compose_service_exists "logto-db"; then
      "${COMPOSE_CMD[@]}" up -d logto-db
    else
      echo "❌ Service 'logto-db' not found in compose configuration"
      exit 1
    fi
    gunzip -c "$BACKUP_DIR/logto_db_${RESTORE_DATE}.sql.gz" | docker exec -i logto-db psql -U "$LOGTO_DB_USER" -d "$LOGTO_DB_NAME"
  fi
fi

echo "Restore complete. Start core services with: ./scripts/start.sh"
