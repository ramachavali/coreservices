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
docker volume rm $(docker volume ls |awk '{print $2}') 2>/dev/null || true

echo -e "🐘 Cleaning up docker images..."
docker rmi $(docker images -a -q) 2>/dev/null || true

echo -e "🐘 Cleaning up docker prune..."
docker system prune -a -f 2>/dev/null || true

echo "Cleanup complete."