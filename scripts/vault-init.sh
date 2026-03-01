#!/usr/bin/env bash

# vault-init.sh - Initialize/unseal Vault and enable baseline audit logging

set -o errexit
set -o nounset

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ -f ./.rendered.env ]; then
  # shellcheck disable=SC1091
  source ./.rendered.env
fi

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
SECRETS_DIR="${PROJECT_ROOT}/secrets"
INIT_FILE="${SECRETS_DIR}/vault-init.json"
AUDIT_FILE_PATH="/vault/logs/audit.log"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

echo "🔐 Initializing Vault..."

if ! docker-compose ps --services --filter "status=running" | grep -q "^vault$"; then
  echo "❌ Vault container is not running."
  echo "Start core services first: ./scripts/start.sh"
  exit 1
fi

is_initialized() {
  docker exec vault vault status -format=json 2>/dev/null | python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("initialized", False)).lower())'
}

is_sealed() {
  docker exec vault vault status -format=json 2>/dev/null | python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("sealed", True)).lower())'
}

if [ "$(is_initialized)" != "true" ]; then
  echo "Vault is not initialized. Running operator init..."
  docker exec vault vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  echo "✅ Vault initialized. Init file saved to: $INIT_FILE"
else
  echo "Vault is already initialized."
  if [ ! -f "$INIT_FILE" ]; then
    echo "⚠️ Local init file not found at $INIT_FILE"
    echo "   Provide unseal key manually if Vault is sealed."
  fi
fi

if [ "$(is_sealed)" = "true" ]; then
  if [ ! -f "$INIT_FILE" ]; then
    echo "❌ Vault is sealed and no init file is available at $INIT_FILE"
    echo "Unseal manually using your stored unseal key:"
    echo "  docker exec -it vault vault operator unseal"
    exit 1
  fi

  UNSEAL_KEY=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("unseal_keys_b64") or [""])[0])' "$INIT_FILE")
  if [ -z "$UNSEAL_KEY" ]; then
    echo "❌ Could not read unseal key from $INIT_FILE"
    exit 1
  fi

  echo "$UNSEAL_KEY" | docker exec -i vault sh -c 'read -r k; vault operator unseal "$k" >/dev/null'
  echo "✅ Vault unsealed"
else
  echo "Vault is already unsealed."
fi

if [ ! -f "$INIT_FILE" ]; then
  echo "⚠️ Skipping audit enable because $INIT_FILE is unavailable"
  exit 0
fi

ROOT_TOKEN=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("root_token", ""))' "$INIT_FILE")
if [ -z "$ROOT_TOKEN" ]; then
  echo "⚠️ Could not read root token from $INIT_FILE; skipping audit enable"
  exit 0
fi

if docker exec vault sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$ROOT_TOKEN' vault audit list -format=json" | grep -q '"file/"'; then
  echo "Audit device already enabled."
else
  echo "Enabling file audit device at $AUDIT_FILE_PATH ..."
  docker exec vault sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$ROOT_TOKEN' vault audit enable file file_path='$AUDIT_FILE_PATH'"
  echo "✅ Audit logging enabled"
fi

echo ""
echo "Vault bootstrap complete."
echo "Next: import environment secrets with ./scripts/vault-import.py"
echo "Security reminders:"
echo "- Move $INIT_FILE to secure offline storage and remove local copy if required."
echo "- Revoke the initial root token after initial configuration."

