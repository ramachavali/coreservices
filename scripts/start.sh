#!/usr/bin/env bash

# Start core services: traefik, vault, logto, logto-db

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

COMPOSE_CMD=(docker-compose)

# Load env if present
if [ -f ./.rendered.env ]; then
  COMPOSE_CMD+=(--env-file ./.rendered.env)
  # shellcheck disable=SC1091
  set -a
  source ./.rendered.env
  set +a
fi

if [ -z "${TAG+x}" ]; then
  TAG=latest
elif [ -f ./.rendered.env ] && ! grep -q '^TAG=' ./.rendered.env; then
  TAG=latest
fi

echo "🚀 Starting core services (traefik, vault, logto, logto-db, core-frontend)..."

LOGTO_DB_USER="${LOGTO_DB_USER:-logto}"
LOGTO_DB_PASSWORD="${LOGTO_DB_PASSWORD:-}"
LOGTO_DB_NAME="${LOGTO_DB_NAME:-logto_db}"
LOGTO_ALTERATION_VERBOSE="${LOGTO_ALTERATION_VERBOSE:-1}"
LOGTO_ALTERATION_TARGET_VERSION="${LOGTO_ALTERATION_TARGET_VERSION:-1.36.0}"
LOGTO_DB_SEED_ON_START="${LOGTO_DB_SEED_ON_START:-1}"

ALTERATION_CMD="npm run cli db alteration deploy -- ${LOGTO_ALTERATION_TARGET_VERSION}"

if [ -z "$LOGTO_DB_PASSWORD" ]; then
  echo "❌ LOGTO_DB_PASSWORD is not set."
  echo "Run ./scripts/setup.sh to render secrets, or set LOGTO_DB_PASSWORD in .rendered.env/.env"
  exit 1
fi

echo "Starting base services (traefik, vault, logto-db)..."
"${COMPOSE_CMD[@]}" up -d traefik logto-db vault

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

echo "Deploying Logto database alterations..."
APP_TYPE_EXISTS=$(docker exec -e PGPASSWORD="$LOGTO_DB_PASSWORD" logto-db \
  psql -U "$LOGTO_DB_USER" -d "$LOGTO_DB_NAME" -tAc \
  "select 1 from pg_type where typname = 'application_type' limit 1;" || true)

if [ "$LOGTO_DB_SEED_ON_START" = "1" ] && [ "$APP_TYPE_EXISTS" != "1" ]; then
  echo "Base Logto schema not found (application_type missing). Bootstrapping database..."
  if [ "$LOGTO_ALTERATION_VERBOSE" = "1" ]; then
    echo "  Running: docker-compose run --rm --no-deps --entrypoint sh -e CI=true -e NPM_CONFIG_LOGLEVEL=verbose logto -lc 'npm run cli db seed -- --swe'"
    "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh -e CI=true -e NPM_CONFIG_LOGLEVEL=verbose logto -lc "npm run cli db seed -- --swe"
  else
    "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh -e CI=true logto -lc "npm run cli db seed -- --swe"
  fi
fi

if [ "$LOGTO_ALTERATION_VERBOSE" = "1" ]; then
  echo "  Target version: ${LOGTO_ALTERATION_TARGET_VERSION}"
  echo "  Running: docker-compose run --rm --no-deps --entrypoint sh -e CI=true -e NPM_CONFIG_LOGLEVEL=verbose -e LOGTO_ALTERATION_TARGET_VERSION logto -lc '${ALTERATION_CMD}'"
  "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh -e CI=true -e NPM_CONFIG_LOGLEVEL=verbose -e LOGTO_ALTERATION_TARGET_VERSION logto -lc "$ALTERATION_CMD"
else
  "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh -e CI=true -e LOGTO_ALTERATION_TARGET_VERSION logto -lc "$ALTERATION_CMD"
fi

echo "Starting Logto and core frontend..."
"${COMPOSE_CMD[@]}" up -d logto core-frontend

echo "Waiting for services to report running status..."
sleep 5

services=(traefik logto logto-db vault core-frontend)
for s in "${services[@]}"; do
  if "${COMPOSE_CMD[@]}" ps --services --filter "status=running" | grep -q "^$s$"; then
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