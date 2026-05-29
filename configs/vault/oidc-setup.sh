#!/bin/sh

set -e

export VAULT_ADDR='http://127.0.0.1:8200'

if ! vault status >/dev/null 2>&1; then
    echo "ERROR: Vault is sealed or not accessible"
    echo "Please unseal Vault first and ensure you have a valid token"
    exit 1
fi

echo "Configuring Vault OIDC authentication..."

if vault auth list | grep -q oidc; then
    echo "✓ OIDC auth method already enabled"
else
    echo "→ Enabling OIDC auth method..."
    vault auth enable oidc
    echo "✓ OIDC auth method enabled"
fi

echo "→ Configuring OIDC provider (Keycloak)..."
vault write auth/oidc/config \
    oidc_discovery_url="https://auth.local/realms/homelab" \
    oidc_client_id="vault" \
    oidc_client_secret="${VAULT_OIDC_CLIENT_SECRET}" \
    default_role="homelab-user"
echo "✓ OIDC provider configured"

echo "→ Creating admin role..."
vault write auth/oidc/role/homelab-admin \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.local/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="admin" \
    ttl=1h
echo "✓ Admin role created"

echo "→ Creating user role..."
vault write auth/oidc/role/homelab-user \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.local/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="default" \
    ttl=1h
echo "✓ User role created"

echo "→ Creating policies..."

vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
echo "✓ Admin policy created"

vault policy write default - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
echo "✓ Default policy created"

echo "→ Setting up group mappings..."

vault write identity/group name="keycloak-admins" \
    policies="admin" \
    type="external" >/dev/null 2>&1 || echo "  (Group may already exist)"

ADMIN_GROUP_ID=$(vault read -field=id identity/group/name/keycloak-admins)
echo "  Admin group ID: ${ADMIN_GROUP_ID}"

OIDC_ACCESSOR=$(vault auth list -format=json | jq -r '.["oidc/"].accessor')
echo "  OIDC accessor: ${OIDC_ACCESSOR}"

vault write identity/group-alias name="homelab-admins" \
    mount_accessor="${OIDC_ACCESSOR}" \
    canonical_id="${ADMIN_GROUP_ID}" >/dev/null 2>&1 || echo "  (Alias may already exist)"
echo "✓ Group mappings configured"

echo "Vault OIDC configuration complete."
echo "Next steps:"
echo "1. Configure Keycloak client 'vault' with:"
echo "   - Client ID: vault"
echo "   - Valid Redirect URIs:"
echo "     * https://vault.local/ui/vault/auth/oidc/oidc/callback"
echo "     * http://localhost:8250/oidc/callback"
echo "2. Add 'groups' mapper to include group membership"
echo "3. Create 'homelab-admins' group in Keycloak"
echo "4. Test login at: https://vault.local"
echo "CLI login command:"
echo "  vault login -method=oidc role=homelab-admin"
