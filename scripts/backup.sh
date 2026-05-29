#!/usr/bin/env bash

# Backup core services: vault, traefik certs/logs

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

if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
fi

BACKUP_DIR="${BACKUP_LOCATION:-$HOME/coreservices-backups}"
DATE=$(date +%Y%m%d_%H%M%S)
COMPRESS=true

mkdir -p "$BACKUP_DIR"

echo "💾 Core services backup -> $BACKUP_DIR"

echo "  - Backing up named volumes from compose..."
volumes=()
while IFS= read -r v; do
  [ -n "$v" ] && volumes+=("$v")
done < <(compose_volume_list)

for volume in "${volumes[@]}"; do
  echo "    • $volume"
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker run --rm -v "$volume:/data" -v "$BACKUP_DIR":/backup alpine sh -c "cd /data && tar czf /backup/${volume}_${DATE}.tar.gz ." 2>/dev/null || true
  else
    echo "      ⚠️ Volume $volume not found"
  fi
done

echo "Backup complete. Files in: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | sed -n '1,100p'
