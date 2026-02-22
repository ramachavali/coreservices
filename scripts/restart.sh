#!/usr/bin/env bash

# Restart core services via compose service loop and redeploy Logto DB alterations.

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Load env if present
if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
fi

echo "🔄 Restarting core services..."

services=()
while IFS= read -r service; do
  services+=("$service")
done < <(docker-compose config --services)
for service in "${services[@]}"; do
  echo "Restarting $service..."
  docker-compose restart "$service" || docker-compose up -d "$service"
done

if [ -x ./scripts/logto-alteration-deploy.sh ]; then
  echo "Deploying Logto DB alterations..."
  ./scripts/logto-alteration-deploy.sh
fi

echo "Checking final service status..."
docker-compose ps

echo "Restart flow complete."
