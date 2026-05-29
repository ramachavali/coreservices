#!/usr/bin/env bash

# Start core services via compose service loops.

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

COMPOSE_CMD=(docker-compose)

# Load env if present
if [ -f ./.rendered.env ]; then
  COMPOSE_CMD+=(--env-file ./.rendered.env)
  # shellcheck disable=SC1091
  set -a
  source ./.rendered.env
  set +a
fi

if [ -z "${TAG+x}" ]; then
  TAG=latest
elif [ -f ./.rendered.env ] && ! grep -q '^TAG=' ./.rendered.env; then
  TAG=latest
fi

echo "🚀 Starting core services (traefik, vault, grafana, core-frontend)..."

in_array() {
  local needle="$1"
  shift
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

wait_for_keycloak() {
  local url="${KEYCLOAK_URL:-https://auth.local}"
  local max_attempts=30
  local attempt=0
  echo "Waiting for Keycloak to be ready at ${url}..."
  while [ "$attempt" -lt "$max_attempts" ]; do
    local status
    status=$(curl -sk -o /dev/null -w "%{http_code}" "${url}/health/ready" 2>/dev/null || echo "000")
    if [ "$status" = "200" ]; then
      echo "  ✅ Keycloak is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done
  echo "  ⚠️ Keycloak did not become ready after $((max_attempts * 5))s - skipping realm init"
  return 1
}

_KC_TOKEN=""

_kc_create_client() {
  local url="$1"
  local realm="$2"
  local client_id="$3"
  local client_name="$4"
  local redirect_uris="$5"
  local description="$6"

  echo "  → Creating client '${client_id}'..."

  local existing
  existing=$(curl -s -X GET "${url}/admin/realms/${realm}/clients?clientId=${client_id}" \
    -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.[0].clientId')

  if [ "$existing" = "$client_id" ]; then
    echo "    ✓ Client '${client_id}' already exists"
    return
  fi

  curl -s -X POST "${url}/admin/realms/${realm}/clients" \
    -H "Authorization: Bearer ${_KC_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"${client_id}\",
      \"name\": \"${client_name}\",
      \"description\": \"${description}\",
      \"enabled\": true,
      \"clientAuthenticatorType\": \"client-secret\",
      \"redirectUris\": ${redirect_uris},
      \"webOrigins\": [\"+\"],
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"standardFlowEnabled\": true,
      \"implicitFlowEnabled\": false,
      \"directAccessGrantsEnabled\": true,
      \"serviceAccountsEnabled\": false,
      \"authorizationServicesEnabled\": false,
      \"fullScopeAllowed\": true
    }" > /dev/null

  echo "    ✓ Client '${client_id}' created"

  local client_uuid
  client_uuid=$(curl -s -X GET "${url}/admin/realms/${realm}/clients?clientId=${client_id}" \
    -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.[0].id')

  curl -s -X POST "${url}/admin/realms/${realm}/clients/${client_uuid}/protocol-mappers/models" \
    -H "Authorization: Bearer ${_KC_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "groups",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-group-membership-mapper",
      "consentRequired": false,
      "config": {
        "full.path": "false",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "groups",
        "userinfo.token.claim": "true"
      }
    }' > /dev/null

  local secret
  secret=$(curl -s -X GET "${url}/admin/realms/${realm}/clients/${client_uuid}/client-secret" \
    -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.value')

  echo "    ✓ Groups mapper added"
  local env_key="KEYCLOAK_$(echo "${client_id}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_CLIENT_SECRET"
  echo "    Client Secret: ${secret}"
  echo "    Add to .env: ${env_key}=${secret}"
}

init_keycloak_realm() {
  local url="${KEYCLOAK_URL:-https://auth.local}"
  local admin_user="${KEYCLOAK_ADMIN_USER:-admin}"
  local admin_password="${KEYCLOAK_ADMIN_PASSWORD:-}"
  local realm="homelab"

  if [ -z "$admin_password" ]; then
    echo "  ⚠️ KEYCLOAK_ADMIN_PASSWORD not set - skipping realm initialization"
    return 0
  fi

  echo "Initializing Keycloak realm '${realm}'..."

  _KC_TOKEN=$(curl -s -X POST "${url}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${admin_user}" \
    -d "password=${admin_password}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')

  if [ "$_KC_TOKEN" = "null" ] || [ -z "$_KC_TOKEN" ]; then
    echo "  ❌ Failed to authenticate with Keycloak - skipping realm init"
    return 1
  fi

  echo "  ✓ Authenticated with Keycloak"

  local realm_status
  realm_status=$(curl -s -X GET "${url}/admin/realms/${realm}" \
    -H "Authorization: Bearer ${_KC_TOKEN}" -o /dev/null -w "%{http_code}")

  if [ "$realm_status" = "200" ]; then
    echo "  ✓ Realm '${realm}' already exists"
  else
    curl -s -X POST "${url}/admin/realms" \
      -H "Authorization: Bearer ${_KC_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"realm\": \"${realm}\",
        \"enabled\": true,
        \"displayName\": \"Homelab Services\",
        \"displayNameHtml\": \"<b>Homelab</b> Services\",
        \"sslRequired\": \"external\",
        \"registrationAllowed\": false,
        \"rememberMe\": true,
        \"verifyEmail\": false,
        \"loginWithEmailAllowed\": true,
        \"duplicateEmailsAllowed\": false,
        \"resetPasswordAllowed\": true,
        \"editUsernameAllowed\": false,
        \"bruteForceProtected\": true,
        \"permanentLockout\": false,
        \"maxFailureWaitSeconds\": 900,
        \"minimumQuickLoginWaitSeconds\": 60,
        \"waitIncrementSeconds\": 60,
        \"quickLoginCheckMilliSeconds\": 1000,
        \"maxDeltaTimeSeconds\": 43200,
        \"failureFactor\": 30
      }" > /dev/null
    echo "  ✓ Realm '${realm}' created"
  fi

  for group in "homelab-admins" "homelab-users" "homelab-monitoring"; do
    local existing_group
    existing_group=$(curl -s -X GET "${url}/admin/realms/${realm}/groups?search=${group}" \
      -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.[0].name')
    if [ "$existing_group" = "$group" ]; then
      echo "  ✓ Group '${group}' already exists"
    else
      curl -s -X POST "${url}/admin/realms/${realm}/groups" \
        -H "Authorization: Bearer ${_KC_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${group}\"}" > /dev/null
      echo "  ✓ Group '${group}' created"
    fi
  done

  _kc_create_client "$url" "$realm" "openwebui" "Open WebUI" '["https://open-webui.local/oauth/callback"]' "AI Chat Interface"
  _kc_create_client "$url" "$realm" "n8n" "n8n Workflow Automation" '["https://n8n.local/rest/oauth2-credential/callback"]' "Workflow Automation Platform"
  _kc_create_client "$url" "$realm" "litellm" "LiteLLM Proxy" '["https://litellm.local/sso/callback"]' "LLM Proxy and Routing"
  _kc_create_client "$url" "$realm" "grafana" "Grafana Monitoring" '["https://grafana.local/login/generic_oauth"]' "Monitoring and Visualization"
  _kc_create_client "$url" "$realm" "vault" "HashiCorp Vault" '["https://vault.local/ui/vault/auth/oidc/oidc/callback","http://localhost:8250/oidc/callback"]' "Secrets Management"
  _kc_create_client "$url" "$realm" "traefik-forward-auth" "Traefik ForwardAuth" '["https://auth.local/oauth/callback"]' "Traefik Authentication Middleware"
  _kc_create_client "$url" "$realm" "ai-portal" "AI Services Portal" '["https://portal.local/callback"]' "AI Stack Landing Page"
  _kc_create_client "$url" "$realm" "core-portal" "Core Services Portal" '["https://core.local/callback"]' "Core Services Landing Page"

  echo "Keycloak realm initialization complete."
  echo "Next steps:"
  echo "  1. Copy client secrets above to your .env file"
  echo "  2. Create users in Keycloak admin console: ${url}"
  echo "  3. Assign users to groups: homelab-admins, homelab-users, homelab-monitoring"
}

echo "Starting base services (traefik, vault)..."
all_services=()
while IFS= read -r service; do
  all_services+=("$service")
done < <("${COMPOSE_CMD[@]}" config --services)
base_services=(traefik vault)

for service in "${base_services[@]}"; do
  if in_array "$service" "${all_services[@]}"; then
    echo "  ▶ Starting ${service}..."
    "${COMPOSE_CMD[@]}" up -d "$service"
  fi
done

if in_array "keycloak" "${all_services[@]}"; then
  echo "Starting Keycloak..."
  "${COMPOSE_CMD[@]}" up -d keycloak
  if wait_for_keycloak; then
    init_keycloak_realm
  fi
fi

echo "Starting remaining services..."
for service in "${all_services[@]}"; do
  if ! in_array "$service" "${base_services[@]}" && [ "$service" != "keycloak" ]; then
    echo "  ▶ Starting ${service}..."
    "${COMPOSE_CMD[@]}" up -d "$service"
  fi
done

echo "Waiting for services to report running status..."
sleep 5

services=("${all_services[@]}")
for s in "${services[@]}"; do
  if "${COMPOSE_CMD[@]}" ps --services --filter "status=running" | grep -q "^$s$"; then
    echo "  ✅ $s is running"
  else
    echo "  ⚠️ $s is not running yet - check logs with: docker-compose logs $s"
  fi
done

echo -e "\nCore services started."
echo "Traefik dashboard: https://traefik.local"
echo "Grafana: https://grafana.local"
echo "Vault UI: https://vault.local"
echo "Keycloak: https://auth.local"
echo "Core Frontend: https://core.local"
