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

echo "Ensuring database is running..."
docker-compose up -d logto-db

echo "Restarting logto container..."
docker-compose restart logto || docker-compose up -d logto

echo "Deploying alterations after restart..."
./scripts/logto-alteration-deploy.sh

echo "Checking final service status..."
docker-compose ps logto logto-db core-frontend

echo "Restart flow complete."
