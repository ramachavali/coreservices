#!/usr/bin/env bash

# Stop core services only

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

FORCE=false
REMOVE_VOLUMES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true; shift;;
        --volumes|-v)
            REMOVE_VOLUMES=true; shift;;
        --help|-h)
            echo "Usage: $0 [--force] [--volumes]"; exit 0;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
done

echo "🛑 Stopping core services..."

if [ "$FORCE" = true ]; then
    echo "⚡ Force stopping core services..."
    docker-compose kill traefik logto logto-db vault core-frontend || true
else
    echo "🔄 Gracefully stopping core services..."
    docker-compose stop traefik logto logto-db vault core-frontend || true
fi

echo "🧹 Bringing down containers (compose down)..."
if [ "$REMOVE_VOLUMES" = true ]; then
    echo "🗑️ Removing volumes for core services..."
    docker-compose down -v
else
    docker-compose down
fi

echo "Done."

echo "Useful commands:"
echo "  docker-compose ps" 
echo "  docker-compose logs [service]"
