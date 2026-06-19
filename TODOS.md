# TODOS

Deferred work with enough context to pick up later.

---

## Vault Database Secrets Engine

**What:** Configure Vault's database secrets engine to dynamically issue short-lived
Postgres credentials for ai-stack services (n8n, OpenWebUI, LiteLLM, rag apps) instead
of using static passwords baked into `.rendered.env`.

**Why:** Static `POSTGRES_PASSWORD` in `.env` is a long-lived credential. If it leaks
(backup, log, debug output), it's permanent. Vault dynamic credentials are scoped leases
(e.g., 1h TTL) that auto-expire and rotate. Standard practice when Vault is already in
the stack.

**Current state:** Vault is running with file backend. OIDC auth against Keycloak is
planned. The `vault_oidc` Postgres database was removed from this plan because Vault doesn't
need its own DB for OIDC. Dynamic secrets would be a separate Vault secrets engine mount.

**How to start:**
1. Enable the database secrets engine: `vault secrets enable database`
2. Configure the ai-stack postgres connection under the engine
3. Create roles with `CREATE USER ... WITH PASSWORD '{{password}}'` templates
4. Update docker-compose env blocks to fetch credentials from Vault Agent or `vault read`

**Blocked by:** Vault must be initialized, unsealed, and Keycloak OIDC auth working first.

**Effort:** human ~4h / CC ~30min (Vault config + compose Vault Agent sidecar pattern)
