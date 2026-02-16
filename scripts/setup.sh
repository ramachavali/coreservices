#!/usr/bin/env bash

# Minimal setup for core services folder

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "⚙️ Setting up core services environment..."

render_env() {
  local template_file="$1"
  local env_file="${PROJECT_ROOT}/.env"
  local rendered_file="${PROJECT_ROOT}/.rendered.env"

  : > "$env_file"
  : > "$rendered_file"

  while IFS= read -r line || [ -n "$line" ]; do
    cleaned_line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]*=[[:space:]]*/=/' | tr -d '\r')

    if [[ -z "$cleaned_line" || "$cleaned_line" == "#"* ]]; then
      continue
    fi

    if [[ "$cleaned_line" == *"="* ]]; then
      set +u
      rendered=$(eval "echo \"$cleaned_line\"")
      set -u

      echo "$rendered" >> "$env_file"
      echo "$rendered" >> "$rendered_file"
      export "$rendered"
    fi
  done < "$template_file"
}

if [ -f scripts/.unrendered.env ]; then
  if [ -f ./.rendered.env ]; then
    echo "Using existing .rendered.env (kept as-is)."
    echo "Delete .env/.rendered.env and re-run setup to regenerate secrets."
  else
    echo "Rendering environment from scripts/.unrendered.env"
    render_env scripts/.unrendered.env
    echo "Created .env and .rendered.env from template with generated secrets"
  fi
else
  echo "No scripts/.unrendered.env found; create .env manually with required variables"
fi

# Create minimal data directories for core services
mkdir -p data/vault
mkdir -p data/traefik
mkdir -p data/logto

chmod 700 data/vault || true

echo "Making management scripts executable"
chmod +x scripts/*.sh || true

echo "Setup complete. Review .env and then run: ./scripts/start.sh"