#!/usr/bin/env bash

# Deploy Logto DB alterations (safe to run after container restart or upgrade).

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

LOGTO_ALTERATION_TARGET_VERSION="${LOGTO_ALTERATION_TARGET_VERSION:-1.36.0}"
LOGTO_ALTERATION_VERBOSE="${LOGTO_ALTERATION_VERBOSE:-1}"

echo "Deploying Logto database alterations..."
echo "Target version: ${LOGTO_ALTERATION_TARGET_VERSION}"

echo "Starting logto-db if needed..."
"${COMPOSE_CMD[@]}" up -d logto-db

ALTERATION_CMD="npm run cli db alteration deploy -- ${LOGTO_ALTERATION_TARGET_VERSION}"

if [ "$LOGTO_ALTERATION_VERBOSE" = "1" ]; then
  echo "Running: docker-compose run --rm --no-deps --entrypoint sh -e CI=true -e NPM_CONFIG_LOGLEVEL=verbose -e LOGTO_ALTERATION_TARGET_VERSION logto -lc '${ALTERATION_CMD}'"
  "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh -e CI=true -e NPM_CONFIG_LOGLEVEL=verbose -e LOGTO_ALTERATION_TARGET_VERSION logto -lc "$ALTERATION_CMD"
else
  "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh -e CI=true -e LOGTO_ALTERATION_TARGET_VERSION logto -lc "$ALTERATION_CMD"
fi

echo "Restarting Logto service..."
"${COMPOSE_CMD[@]}" up -d --force-recreate logto

echo "Done. Check logs with: docker-compose logs -f logto"
