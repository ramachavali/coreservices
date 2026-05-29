#!/usr/bin/env bash

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

echo "Checking final service status..."
docker-compose ps

echo "Restart flow complete."
