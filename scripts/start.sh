#!/usr/bin/env bash

# Start core services: traefik, vault, logto, logto-db

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Load env if present
if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
fi

echo "🚀 Starting core services (traefik, vault, logto, logto-db, core-frontend)..."

LOGTO_DB_USER="${LOGTO_DB_USER:-logto}"
LOGTO_DB_PASSWORD="${LOGTO_DB_PASSWORD:-}"
LOGTO_DB_NAME="${LOGTO_DB_NAME:-logto_db}"

if [ -z "$LOGTO_DB_PASSWORD" ]; then
  echo "❌ LOGTO_DB_PASSWORD is not set."
  echo "Run ./scripts/setup.sh to render secrets, or set LOGTO_DB_PASSWORD in .rendered.env/.env"
  exit 1
fi

docker-compose up -d traefik logto logto-db vault core-frontend

echo "Checking logto-db readiness..."
for i in {1..20}; do
  if docker exec logto-db pg_isready -U "$LOGTO_DB_USER" -d "$LOGTO_DB_NAME" >/dev/null 2>&1; then
    echo "  ✅ logto-db is ready"
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "  ❌ logto-db did not become ready in time"
    echo "  Check logs: docker-compose logs logto-db"
    exit 1
  fi
  sleep 2
done

echo "Waiting for services to report running status..."
sleep 5

services=(traefik logto logto-db vault core-frontend)
for s in "${services[@]}"; do
  if docker-compose ps --services --filter "status=running" | grep -q "^$s$"; then
    echo "  ✅ $s is running"
  else
    echo "  ⚠️ $s is not running yet - check logs with: docker-compose logs $s"
  fi
done

echo ""
echo "Core services started."
echo "Traefik dashboard: https://traefik.local (if configured)"
echo "Logto (auth): https://auth.local (if configured)"
echo "Vault UI: http://localhost:8200 (if accessible)"
echo "Core Frontend: https://core.local"