#!/opt/homebrew/bin/bash

# Start core services via compose service loops.

set -o errexit
set -o nounset
set -o pipefail

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

echo "🚀 Starting core services (traefik, vault, grafana, core-frontend)..."

in_array() {
  local needle="$1"
  shift
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

echo "Starting base services (traefik, vault)..."
all_services=()
while IFS= read -r service; do
  all_services+=("$service")
done < <("${COMPOSE_CMD[@]}" config --services)
base_services=(traefik vault)

for service in "${base_services[@]}"; do
  if in_array "$service" "${all_services[@]}"; then
    echo "  ▶ Starting ${service}..."
    "${COMPOSE_CMD[@]}" up -d "$service"
  fi
done

if in_array "keycloak" "${all_services[@]}"; then
  echo "Starting Keycloak..."
  "${COMPOSE_CMD[@]}" up -d keycloak
  echo "  → Run ./scripts/keycloak-init.sh once Keycloak is healthy to initialize the realm."
fi

echo "Starting remaining services..."
for service in "${all_services[@]}"; do
  if ! in_array "$service" "${base_services[@]}" && [ "$service" != "keycloak" ]; then
    echo "  ▶ Starting ${service}..."
    "${COMPOSE_CMD[@]}" up -d "$service"
  fi
done

echo "Waiting for services to report running status..."
sleep 5

services=("${all_services[@]}")
for s in "${services[@]}"; do
  if "${COMPOSE_CMD[@]}" ps --services --filter "status=running" | grep -q "^$s$"; then
    echo "  ✅ $s is running"
  else
    echo "  ⚠️ $s is not running yet - check logs with: docker-compose logs $s"
  fi
done

echo -e "\nCore services started."
echo "Traefik dashboard: https://traefik.local"
echo "Grafana: https://grafana.local"
echo "Vault UI: https://vault.local"
echo "Keycloak: https://auth.local"
echo "Core Frontend: https://core.local"
