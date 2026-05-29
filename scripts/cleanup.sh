#!/usr/bin/env bash

# Lightweight cleanup for core services folder

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🧹 Core services cleanup"

read -p "Do you want to proceed with cleanup? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "\n🔹 Starting cleanup..."

echo -e "\n🛑 Stopping core services before cleanup..."
docker-compose down --remove-orphans || true

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

echo -e "🐘 Cleaning up environment files..."
safe_remove "./.env" "remove .env file"
safe_remove "./.rendered.env" "remove .env file"

remove_docker_volume() {
    local volume="${1}"

    if docker volume inspect "$volume" >/dev/null 2>&1; then
        if docker volume rm "$volume" >/dev/null 2>&1; then
            echo -e "  ✅ Removed volume: $volume"
        else
            echo -e "  ⚠️  Skipped volume (in use): $volume"
        fi
    else
        echo -e "  ℹ️  Volume not found: $volume"
    fi
}

echo -e "🐘 Cleaning up docker volumes..."
compose_volumes=()
while IFS= read -r volume; do
    compose_volumes+=("$volume")
done < <(docker-compose config --volumes 2>/dev/null | sed '/^$/d' | sort -u)

if [ "${#compose_volumes[@]}" -gt 0 ]; then
    for volume in "${compose_volumes[@]}"; do
        remove_docker_volume "$volume"
    done
else
    echo -e "  ⚠️  Could not resolve compose volumes; using fallback volume list"
    for volume in traefik_certs traefik_logs vault_data vault_logs grafana_data loki_data; do
        remove_docker_volume "$volume"
    done
fi

echo -e "🐘 Cleaning up docker images..."
docker image prune -f || true

echo -e "🐘 Cleaning up docker prune..."
docker system prune -a -f 2>/dev/null || true

echo "Cleanup complete."