#!/usr/bin/env bash

# Lightweight cleanup for core services folder

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🧹 Core services cleanup"

# Ask for confirmation
read -p "Do you want to proceed with cleanup? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "🔹 Starting cleanup..."
echo ""

echo -e "🛑 Stopping core services before cleanup..."
docker-compose down --remove-orphans || true

# Function to safely remove file/directory
safe_remove() {
    local path="${1}"
    local description="${2}"
    
    if [ -e "$path" ]; then
        echo -e "  ⚠️  Removing: $description"
        rm -rf "$path"
        echo -e "  ✅ Removed: $path"
    else
        echo -e "  ℹ️  Not found (already clean): $path"
    fi
}

echo "Removing .DS_Store files and temporary artifacts..."
find . -name ".DS_Store" -type f -delete 2>/dev/null || true
find . -name "*.tmp" -type f -delete 2>/dev/null || true

# 7. Remove .env
echo -e "🐘 Cleaning up environment files..."
safe_remove "./.env" "remove .env file"
safe_remove "./.rendered.env" "remove .env file"

echo -e "🐘 Cleaning up docker volumes..."
for volume in traefik_certs traefik_logs vault_data vault_logs logto_data logto_db_data_pg18 grafana_data; do
    if docker volume inspect "$volume" >/dev/null 2>&1; then
        if docker volume rm "$volume" >/dev/null 2>&1; then
            echo -e "  ✅ Removed volume: $volume"
        else
            echo -e "  ⚠️  Skipped volume (in use): $volume"
        fi
    else
        echo -e "  ℹ️  Volume not found: $volume"
    fi
done

echo -e "🐘 Cleaning up docker images..."
docker image prune -f || true

echo -e "🐘 Cleaning up docker prune..."
docker system prune -a -f 2>/dev/null || true

echo "Cleanup complete."