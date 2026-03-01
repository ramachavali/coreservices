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

is_url_safe_secret() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9._~-]+$ ]]
}

upsert_env_var() {
  local file_path="$1"
  local var_name="$2"
  local var_value="$3"

  if [ ! -f "$file_path" ]; then
    return
  fi

  local tmp_file="${file_path}.tmp"
  awk -v key="$var_name" -v value="$var_value" '
    BEGIN { updated=0 }
    $0 ~ ("^" key "=") {
      print key "=\"" value "\""
      updated=1
      next
    }
    { print }
    END {
      if (!updated) {
        print key "=\"" value "\""
      }
    }
  ' "$file_path" > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

ensure_url_safe_secret() {
  local var_name="$1"
  local hex_bytes="$2"
  local current_value="${!var_name:-}"

  if [ -z "$current_value" ] || ! is_url_safe_secret "$current_value"; then
    local new_value
    new_value="$(openssl rand -hex "$hex_bytes")"

    export "${var_name}=${new_value}"
    upsert_env_var "${PROJECT_ROOT}/.env" "$var_name" "$new_value"
    upsert_env_var "${PROJECT_ROOT}/.rendered.env" "$var_name" "$new_value"

    echo "⚠️ ${var_name} was empty or URL-unsafe and has been rotated"
  fi
}

refresh_logto_database_urls() {
  local user="${LOGTO_DB_USER:-logto}"
  local password="${LOGTO_DB_PASSWORD:-}"
  local host="${LOGTO_DB_HOST:-logto-db}"
  local db_name="${LOGTO_DB_NAME:-logto_db}"
  local db_url="postgres://${user}:${password}@${host}:5432/${db_name}"

  export "LOGTO_DATABASE_URL=${db_url}"
  export "DB_URL=${db_url}"

  upsert_env_var "${PROJECT_ROOT}/.env" "LOGTO_DATABASE_URL" "$db_url"
  upsert_env_var "${PROJECT_ROOT}/.env" "DB_URL" "$db_url"
  upsert_env_var "${PROJECT_ROOT}/.rendered.env" "LOGTO_DATABASE_URL" "$db_url"
  upsert_env_var "${PROJECT_ROOT}/.rendered.env" "DB_URL" "$db_url"
}

setup_tls_certificates() {
  local pki_script="${PROJECT_ROOT}/scripts/pki-build.sh"
  local pki_dir="${PROJECT_ROOT}/pki"
  local certs_dir="${pki_dir}/certs"
  local ca_name="FoolsM4 Local Root CA"
  local primary_hostname="foolsm4.local"

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

  echo "Generating local shared TLS certificates for services..."
  local pki_args=(
    --out-dir "$pki_dir"
    --ca-name "$ca_name"
    --hostname "$primary_hostname"
  )
  for san in "${sans[@]}"; do
    pki_args+=(--san "$san")
  done

  "$pki_script" "${pki_args[@]}"

  if [ ! -f "$certs_dir/cert.pem" ] || [ ! -f "$certs_dir/key.pem" ]; then
    echo "❌ TLS cert/key not found under $certs_dir"
    echo "❌ Expected cert.pem and key.pem after PKI generation"
    exit 1
  fi

  echo "Installing shared TLS certificate into Docker volume traefik_certs..."
  docker volume create traefik_certs >/dev/null
  local sync_container
  sync_container="$(docker create -v traefik_certs:/certs alpine:3.20 sh -ec 'chmod 644 /certs/cert.pem && chmod 600 /certs/key.pem')"
  docker cp "$certs_dir/cert.pem" "${sync_container}:/certs/cert.pem"
  docker cp "$certs_dir/key.pem" "${sync_container}:/certs/key.pem"
  docker start "$sync_container" >/dev/null
  docker rm "$sync_container" >/dev/null

  echo "✅ Shared TLS certificate installed"
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

if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
elif [ -f ./.env ]; then
  # shellcheck disable=SC1091
  source ./.env
fi

ensure_url_safe_secret "LOGTO_DB_PASSWORD" 24
refresh_logto_database_urls

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