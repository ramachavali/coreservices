#!/usr/bin/env bash

# Restart core auth services and redeploy Logto DB alterations.

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Load env if present
if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
fi

echo "🔄 Restarting Logto services..."

services=(logto-db logto vault core-frontend)
for service in "${services[@]}"; do
  echo "Restarting $service..."
  docker-compose restart "$service" || docker-compose up -d "$service"
done

echo "Checking final service status..."
docker-compose ps logto logto-db core-frontend

echo "Restart flow complete."