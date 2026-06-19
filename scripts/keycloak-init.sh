#!/opt/homebrew/bin/bash

# Initialize Keycloak realm, groups, and OIDC clients.
# Run once manually after Keycloak is up: ./scripts/keycloak-init.sh

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  set -a
  source ./.rendered.env
  set +a
fi

wait_for_keycloak() {
  local container="keycloak"
  local max_attempts=36
  local attempt=0
  echo "Waiting for Keycloak to be ready..."
  while [ "$attempt" -lt "$max_attempts" ]; do
    if docker exec "$container" bash -c \
      'exec 3<>/dev/tcp/localhost/9000 2>/dev/null && printf "GET /health/ready HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3 && grep -q UP <&3' \
      2>/dev/null; then
      echo "  ✅ Keycloak is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done
  echo "  ⚠️ Keycloak did not become ready after $((max_attempts * 5))s"
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
  existing=$(curl -sk --max-time 15 -X GET "${url}/admin/realms/${realm}/clients?clientId=${client_id}" \
    -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.[0].clientId')

  if [ "$existing" = "$client_id" ]; then
    echo "    ✓ Client '${client_id}' already exists"
    return
  fi

  curl -sk --max-time 15 -X POST "${url}/admin/realms/${realm}/clients" \
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
  client_uuid=$(curl -sk --max-time 15 -X GET "${url}/admin/realms/${realm}/clients?clientId=${client_id}" \
    -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.[0].id')

  curl -sk --max-time 15 -X POST "${url}/admin/realms/${realm}/clients/${client_uuid}/protocol-mappers/models" \
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
  secret=$(curl -sk --max-time 15 -X GET "${url}/admin/realms/${realm}/clients/${client_uuid}/client-secret" \
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
    echo "  ❌ KEYCLOAK_ADMIN_PASSWORD not set in .rendered.env"
    return 1
  fi

  echo "Initializing Keycloak realm '${realm}'..."

  _KC_TOKEN=$(curl -sk --max-time 15 -X POST "${url}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${admin_user}" \
    -d "password=${admin_password}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')

  if [ "$_KC_TOKEN" = "null" ] || [ -z "$_KC_TOKEN" ]; then
    echo "  ❌ Failed to authenticate with Keycloak at ${url}"
    return 1
  fi

  echo "  ✓ Authenticated with Keycloak"

  local realm_status
  realm_status=$(curl -sk --max-time 15 -X GET "${url}/admin/realms/${realm}" \
    -H "Authorization: Bearer ${_KC_TOKEN}" -o /dev/null -w "%{http_code}")

  if [ "$realm_status" = "200" ]; then
    echo "  ✓ Realm '${realm}' already exists"
  else
    curl -sk --max-time 15 -X POST "${url}/admin/realms" \
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
    existing_group=$(curl -sk --max-time 15 -X GET "${url}/admin/realms/${realm}/groups?search=${group}" \
      -H "Authorization: Bearer ${_KC_TOKEN}" | jq -r '.[0].name')
    if [ "$existing_group" = "$group" ]; then
      echo "  ✓ Group '${group}' already exists"
    else
      curl -sk --max-time 15 -X POST "${url}/admin/realms/${realm}/groups" \
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

wait_for_keycloak
init_keycloak_realm
