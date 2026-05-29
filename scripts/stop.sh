#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

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

services=()
while IFS= read -r service; do
    services+=("$service")
done < <(docker-compose config --services)

if [ "$FORCE" = true ]; then
    echo "⚡ Force stopping core services..."
    for (( idx=${#services[@]}-1; idx>=0; idx-- )); do
        service="${services[$idx]}"
        echo "  ⏹ Killing ${service}..."
        docker-compose kill "$service" || true
    done
else
    echo "🔄 Gracefully stopping core services..."
    for (( idx=${#services[@]}-1; idx>=0; idx-- )); do
        service="${services[$idx]}"
        echo "  ⏹ Stopping ${service}..."
        docker-compose stop "$service" || true
    done
fi

echo "🧹 Bringing down containers (compose down)..."
if [ "$REMOVE_VOLUMES" = true ]; then
    echo "🗑️ Removing volumes for core services..."
    docker-compose down -v
else
    docker-compose down
fi

echo "Done."
