#!/usr/bin/env bash

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

echo "Restore complete. Start core services with: ./scripts/start.sh"
