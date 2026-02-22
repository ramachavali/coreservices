#!/usr/bin/env bash

# Minimal setup for core services folder

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "⚙️ Setting up core services environment..."

require_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not available"
    echo "Start Docker Desktop/Colima and re-run setup"
    exit 1
  fi
}

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

setup_tls_certificates() {
  local pki_script="${PROJECT_ROOT}/scripts/pki-build.sh"
  local pki_dir="${PROJECT_ROOT}/pki"
  local ca_name="Foolsbook Local Root CA"
  local primary_hostname="traefik.local"

  local sans=(
    "traefik.local"
    "auth.local"
    "grafana.local"
    "core.local"
    "vault.local"
    "open-webui.local"
    "n8n.local"
    "litellm.local"
    "ollama.local"
    "mcpo.local"
    "searxng.local"
    "portal.local"
    "picoclaw.local"
  )

  echo "Generating local TLS certificates for Traefik..."
  local pki_args=(
    --out-dir "$pki_dir"
    --ca-name "$ca_name"
    --hostname "$primary_hostname"
  )
  for san in "${sans[@]}"; do
    pki_args+=(--san "$san")
  done

  "$pki_script" "${pki_args[@]}"

  echo "Installing certificate into Docker volume traefik_certs..."
  docker volume create traefik_certs >/dev/null
  docker run --rm \
    -v traefik_certs:/certs \
    -v "$pki_dir/traefik:/src:ro" \
    alpine:3.20 \
    sh -ec '
      cp /src/cert.pem /certs/cert.pem
      cp /src/key.pem /certs/key.pem
      chmod 644 /certs/cert.pem
      chmod 600 /certs/key.pem
    '

  echo "✅ TLS certificate installed for Traefik"
  echo "   CA bundle: ${pki_dir}/client/ca_bundle.crt"
}

require_docker

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
mkdir -p data/grafana

chmod 700 data/vault || true

echo "Making management scripts executable"
chmod +x scripts/*.sh || true

setup_tls_certificates

echo "Setup complete. Review .env and then run: ./scripts/start.sh"