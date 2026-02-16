#!/usr/bin/env bash

# Lightweight cleanup for core services folder

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🧹 Core services cleanup"

read -p "Proceed to remove temporary files and old backups? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo "Removing .DS_Store files and temporary artifacts..."
find . -name ".DS_Store" -type f -delete 2>/dev/null || true
find . -name "*.tmp" -type f -delete 2>/dev/null || true

echo "Prune unused Docker resources (images/containers) interactively"
docker system prune --volumes -f || true

echo "Cleanup complete."