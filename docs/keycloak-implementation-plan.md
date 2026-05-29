# Keycloak Implementation Plan

## Executive Summary

This document outlines the plan to implement Keycloak as the centralized authentication and identity provider (IdP) for the homelab infrastructure, replacing the placeholder Logto references and providing SSO across all services.

## Architecture Overview

### Deployment Location
**Decision**: Deploy Keycloak in `coreservices-homelab` stack

**Rationale**:
- Core infrastructure service (authentication is foundational)
- Shared across both core and AI services
- Aligns with existing pattern (Traefik, Vault, Grafana in core)
- Single source of truth for identity management

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    coreservices-homelab                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────┐      ┌──────────┐      ┌──────────────┐      │
│  │ Traefik  │─────▶│ Keycloak │◀─────│ PostgreSQL   │      │
│  │ (Proxy)  │      │  (IdP)   │      │ (Auth DB)    │      │
│  └──────────┘      └──────────┘      └──────────────┘      │
│       │                  │                                   │
│       │                  │ OIDC/SAML                        │
│       ▼                  ▼                                   │
│  ┌─────────────────────────────────────────────┐           │
│  │     ForwardAuth Middleware (Traefik)        │           │
│  └─────────────────────────────────────────────┘           │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ Protected Routes
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      ai-stack-homelab                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────┐  ┌─────┐  ┌──────────┐  ┌────────────┐    │
│  │ Open WebUI │  │ n8n │  │ LiteLLM  │  │  Grafana   │    │
│  └────────────┘  └─────┘  └──────────┘  └────────────┘    │
│                                                               │
│  All services protected via Traefik ForwardAuth             │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Keycloak Infrastructure Setup

#### 1.1 Hardened PostgreSQL with pgvector

**Architecture Decision**: Dedicated, hardened PostgreSQL instance with pgvector extension

**Key Features**:
- Separate PostgreSQL container in coreservices-homelab
- pgvector extension enabled for future AI/embedding use cases
- Multiple databases and users for service isolation
- Hardened security configuration
- Independent from AI stack database

**Database Structure**:
- `keycloak` - Keycloak authentication data
- `vault_oidc` - Vault OIDC backend data (if needed)
- Future: Additional auth-related databases

**Users**:
- `keycloak_user` - Keycloak service account (limited to keycloak DB)
- `vault_user` - Vault service account (limited to vault_oidc DB)
- `postgres` - Superuser (admin only)

#### 1.2 Hardened PostgreSQL Service Definition

```yaml
# coreservices-homelab/docker-compose.yml

services:
  auth-postgres:
    image: pgvector/pgvector:pg17
    container_name: auth-postgres
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${AUTH_POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - auth_postgres_data:/var/lib/postgresql/data
      - ./configs/auth-postgres/init-db.sql:/docker-entrypoint-initdb.d/01-init-db.sql:ro
      - ./configs/auth-postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
    networks:
      - core-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '${AUTH_POSTGRES_CPU_LIMIT:-1.0}'
          memory: ${AUTH_POSTGRES_MEMORY_LIMIT:-1G}
        reservations:
          cpus: '${AUTH_POSTGRES_CPU_RESERVATION:-0.25}'
          memory: ${AUTH_POSTGRES_MEMORY_RESERVATION:-256M}

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: keycloak
    restart: unless-stopped
    depends_on:
      auth-postgres:
        condition: service_healthy
    security_opt:
      - no-new-privileges:true
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://auth-postgres:5432/keycloak
      KC_DB_USERNAME: keycloak_user
      KC_DB_PASSWORD: ${KEYCLOAK_DB_PASSWORD}
      KC_HOSTNAME: auth.local
      KC_HOSTNAME_STRICT: false
      KC_HTTP_ENABLED: true
      KC_PROXY: edge
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN_USER}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD}
    command: start
    ports:
      - "8085:8080"
    networks:
      - core-network
    volumes:
      - keycloak_data:/opt/keycloak/data
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=core-network"
      - "traefik.http.routers.keycloak.rule=Host(`auth.local`)"
      - "traefik.http.routers.keycloak.entrypoints=websecure"
      - "traefik.http.routers.keycloak.tls=true"
      - "traefik.http.services.keycloak.loadbalancer.server.port=8080"
    healthcheck:
      test: ["CMD-SHELL", "exec 3<>/dev/tcp/127.0.0.1/8080;echo -e 'GET /health/ready HTTP/1.1\r\nhost: 127.0.0.1\r\nConnection: close\r\n\r\n' >&3;if [ $? -eq 0 ]; then echo 'Healthcheck Successful';exit 0;else echo 'Healthcheck Failed';exit 1;fi;"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s
    deploy:
      resources:
        limits:
          cpus: '${KEYCLOAK_CPU_LIMIT:-2.0}'
          memory: ${KEYCLOAK_MEMORY_LIMIT:-2G}
        reservations:
          cpus: '${KEYCLOAK_CPU_RESERVATION:-0.5}'
          memory: ${KEYCLOAK_MEMORY_RESERVATION:-512M}

volumes:
  auth_postgres_data:
    name: auth_postgres_data
  keycloak_data:
    name: keycloak_data
```
#### 1.3 PostgreSQL Initialization Script

Create `coreservices-homelab/configs/auth-postgres/init-db.sql`:

```sql
-- Authentication PostgreSQL Initialization Script
-- Creates databases and users for Keycloak and Vault OIDC integration

-- Enable pgvector extension on template database
CREATE EXTENSION IF NOT EXISTS vector;

-- Create Keycloak database and user
CREATE DATABASE keycloak;
CREATE USER keycloak_user WITH ENCRYPTED PASSWORD 'KEYCLOAK_DB_PASSWORD_PLACEHOLDER';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak_user;

-- Connect to keycloak database and set permissions
\c keycloak
GRANT ALL ON SCHEMA public TO keycloak_user;
ALTER DATABASE keycloak OWNER TO keycloak_user;

-- Enable pgvector extension in keycloak database
CREATE EXTENSION IF NOT EXISTS vector;

-- Create Vault OIDC database and user (for future Vault integration)
\c postgres
CREATE DATABASE vault_oidc;
CREATE USER vault_user WITH ENCRYPTED PASSWORD 'VAULT_DB_PASSWORD_PLACEHOLDER';
GRANT ALL PRIVILEGES ON DATABASE vault_oidc TO vault_user;

-- Connect to vault_oidc database and set permissions
\c vault_oidc
GRANT ALL ON SCHEMA public TO vault_user;
ALTER DATABASE vault_oidc OWNER TO vault_user;

-- Enable pgvector extension in vault_oidc database
CREATE EXTENSION IF NOT EXISTS vector;

-- Return to postgres database
\c postgres

-- Create read-only monitoring user (optional, for future use)
CREATE USER auth_monitor WITH ENCRYPTED PASSWORD 'AUTH_MONITOR_PASSWORD_PLACEHOLDER';
GRANT CONNECT ON DATABASE keycloak TO auth_monitor;
GRANT CONNECT ON DATABASE vault_oidc TO auth_monitor;

\c keycloak
GRANT USAGE ON SCHEMA public TO auth_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auth_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO auth_monitor;

\c vault_oidc
GRANT USAGE ON SCHEMA public TO auth_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auth_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO auth_monitor;

\c postgres
```

**Note**: Replace password placeholders with actual secure passwords during deployment.

#### 1.4 Hardened PostgreSQL Configuration

Create `coreservices-homelab/configs/auth-postgres/postgresql.conf`:

```conf
# PostgreSQL Configuration for Authentication Services
# Hardened security settings for Keycloak and Vault

# Connection Settings
listen_addresses = '*'
port = 5432
max_connections = 100
superuser_reserved_connections = 3

# Memory Settings
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
work_mem = 4MB

# Write Ahead Log (WAL)
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB
wal_buffers = 16MB

# Query Planning
random_page_cost = 1.1
effective_io_concurrency = 200

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_timezone = 'UTC'

# Security
ssl = off  # Handled by Traefik
password_encryption = scram-sha-256

# Performance
checkpoint_completion_target = 0.9
default_statistics_target = 100

# Locale
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'
default_text_search_config = 'pg_catalog.english'

# pgvector specific
shared_preload_libraries = 'vector'
```


#### 1.5 Environment Variables

```bash
# coreservices-homelab/.env additions

# Authentication PostgreSQL
AUTH_POSTGRES_PASSWORD=<generate-secure-password>
AUTH_POSTGRES_CPU_LIMIT=1.0
AUTH_POSTGRES_MEMORY_LIMIT=1G
AUTH_POSTGRES_CPU_RESERVATION=0.25
AUTH_POSTGRES_MEMORY_RESERVATION=256M

# Keycloak Database Credentials
KEYCLOAK_DB_PASSWORD=<generate-secure-password>
VAULT_DB_PASSWORD=<generate-secure-password>
AUTH_MONITOR_PASSWORD=<generate-secure-password>

# Keycloak Admin
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=<generate-secure-password>

# Keycloak Resource Limits
KEYCLOAK_CPU_LIMIT=2.0
KEYCLOAK_MEMORY_LIMIT=2G
KEYCLOAK_CPU_RESERVATION=0.5
KEYCLOAK_MEMORY_RESERVATION=512M

# Keycloak Client Secrets (generated during realm setup)
KEYCLOAK_OPENWEBUI_CLIENT_SECRET=<to-be-generated>
KEYCLOAK_N8N_CLIENT_SECRET=<to-be-generated>
KEYCLOAK_LITELLM_CLIENT_SECRET=<to-be-generated>
KEYCLOAK_GRAFANA_CLIENT_SECRET=<to-be-generated>
KEYCLOAK_TRAEFIK_CLIENT_SECRET=<to-be-generated>
KEYCLOAK_VAULT_CLIENT_SECRET=<to-be-generated>

# Traefik ForwardAuth
TRAEFIK_FORWARD_AUTH_SECRET=<generate-secure-password>
```

### Phase 2: Keycloak Realm Configuration

#### 2.1 Realm Structure

**Realm Name**: `homelab`

**Purpose**: Single realm for all homelab services

#### 2.2 Client Configurations

Each service requires an OIDC client in Keycloak:

| Service | Client ID | Redirect URIs | Access Type | Notes |
|---------|-----------|---------------|-------------|-------|
| Open WebUI | `openwebui` | `https://open-webui.local/oauth/callback` | confidential | Native OIDC |
| n8n | `n8n` | `https://n8n.local/rest/oauth2-credential/callback` | confidential | Native OIDC |
| LiteLLM | `litellm` | `https://litellm.local/sso/callback` | confidential | ForwardAuth |
| Grafana | `grafana` | `https://grafana.local/login/generic_oauth` | confidential | Generic OAuth |
| **Vault** | `vault` | `https://vault.local/ui/vault/auth/oidc/oidc/callback` | confidential | **OIDC Auth Method** |
| Traefik | `traefik-forward-auth` | `https://auth.local/oauth/callback` | confidential | ForwardAuth |
| Portal (AI) | `ai-portal` | `https://portal.local/callback` | confidential | ForwardAuth |
| Portal (Core) | `core-portal` | `https://core.local/callback` | confidential | ForwardAuth |

#### 2.3 User Federation & Groups

**Initial Setup**:
- Admin user (created during Keycloak initialization)
- Standard user group
- Admin group (for elevated privileges)

**Group Mappings**:
- `homelab-admins` → Full access to all services
- `homelab-users` → Standard access to AI services
- `homelab-monitoring` → Read-only access to Grafana/Traefik

#### 2.4 Realm Configuration Script

Create initialization script: `configs/keycloak/init-realm.sh`

```bash
#!/bin/bash
# Automated realm and client setup using Keycloak Admin CLI
# Run after Keycloak first startup
```

### Phase 3: Traefik ForwardAuth Integration

#### 3.1 ForwardAuth Middleware

**Option A: Traefik Forward Auth (thomseddon/traefik-forward-auth)**
- Lightweight Go application
- Direct OIDC integration
- Simple configuration

**Option B: OAuth2 Proxy**
- More features (email validation, etc.)
- Larger footprint
- More complex configuration

**Recommendation**: Option A for simplicity

#### 3.2 ForwardAuth Service

```yaml
# coreservices-homelab/docker-compose.yml

services:
  traefik-forward-auth:
    image: thomseddon/traefik-forward-auth:latest
    container_name: traefik-forward-auth
    restart: unless-stopped
    depends_on:
      keycloak:
        condition: service_healthy
    security_opt:
      - no-new-privileges:true
    environment:
      PROVIDERS_OIDC_ISSUER_URL: https://auth.local/realms/homelab
      PROVIDERS_OIDC_CLIENT_ID: traefik-forward-auth
      PROVIDERS_OIDC_CLIENT_SECRET: ${KEYCLOAK_TRAEFIK_CLIENT_SECRET}
      SECRET: ${TRAEFIK_FORWARD_AUTH_SECRET}
      AUTH_HOST: auth.local
      COOKIE_DOMAIN: local
      INSECURE_COOKIE: false
      LOG_LEVEL: info
    networks:
      - core-network
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=core-network"
      - "traefik.http.routers.traefik-forward-auth.rule=Host(`auth.local`) && PathPrefix(`/oauth`)"
      - "traefik.http.routers.traefik-forward-auth.entrypoints=websecure"
      - "traefik.http.routers.traefik-forward-auth.tls=true"
      - "traefik.http.services.traefik-forward-auth.loadbalancer.server.port=4181"
      # Middleware definition
      - "traefik.http.middlewares.keycloak-auth.forwardauth.address=http://traefik-forward-auth:4181"
      - "traefik.http.middlewares.keycloak-auth.forwardauth.trustForwardHeader=true"
      - "traefik.http.middlewares.keycloak-auth.forwardauth.authResponseHeaders=X-Forwarded-User"
```

#### 3.3 Traefik Dynamic Configuration

Update `configs/traefik/dynamic.yml`:

```yaml
http:
  middlewares:
    keycloak-auth:
      forwardAuth:
        address: "http://traefik-forward-auth:4181"
        trustForwardHeader: true
        authResponseHeaders:
          - "X-Forwarded-User"
          - "X-Auth-User"
          - "X-Auth-Email"
```

### Phase 4: Service-Specific Integration

#### 4.1 Open WebUI

**Integration Method**: Native OIDC support

**Configuration**:
```yaml
# docker-compose.yml (ai-stack-homelab)
open-webui:
  environment:
    ENABLE_OAUTH_SIGNUP: true
    OAUTH_PROVIDER: oidc
    OAUTH_CLIENT_ID: openwebui
    OAUTH_CLIENT_SECRET: ${KEYCLOAK_OPENWEBUI_CLIENT_SECRET}
    OAUTH_ISSUER: https://auth.local/realms/homelab
    OAUTH_AUTHORIZATION_URL: https://auth.local/realms/homelab/protocol/openid-connect/auth
    OAUTH_TOKEN_URL: https://auth.local/realms/homelab/protocol/openid-connect/token
    OAUTH_USERINFO_URL: https://auth.local/realms/homelab/protocol/openid-connect/userinfo
    OAUTH_SCOPES: openid profile email
  labels:
    - "traefik.http.routers.open-webui.middlewares=keycloak-auth@docker"
```

#### 4.2 n8n

**Integration Method**: Native OAuth2 support

**Configuration**:
```yaml
# docker-compose.yml (ai-stack-homelab)
n8n:
  environment:
    N8N_SSO_OIDC_ENABLED: true
    N8N_SSO_OIDC_ISSUER: https://auth.local/realms/homelab
    N8N_SSO_OIDC_CLIENT_ID: n8n
    N8N_SSO_OIDC_CLIENT_SECRET: ${KEYCLOAK_N8N_CLIENT_SECRET}
    N8N_SSO_OIDC_REDIRECT_URL: https://n8n.local/rest/oauth2-credential/callback
    N8N_SSO_OIDC_SCOPE: openid profile email
  labels:
    - "traefik.http.routers.n8n.middlewares=keycloak-auth@docker"
```

#### 4.3 LiteLLM

**Integration Method**: Traefik ForwardAuth (LiteLLM has limited native SSO)

**Configuration**:
```yaml
# docker-compose.yml (ai-stack-homelab)
litellm:
  labels:
    - "traefik.http.routers.litellm.middlewares=keycloak-auth@docker"
```

#### 4.4 Grafana

**Integration Method**: Native Generic OAuth support

**Configuration**:
```yaml
# docker-compose.yml (coreservices-homelab)
grafana:
  environment:
    GF_AUTH_GENERIC_OAUTH_ENABLED: true
    GF_AUTH_GENERIC_OAUTH_NAME: Keycloak
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID: grafana
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: ${KEYCLOAK_GRAFANA_CLIENT_SECRET}
    GF_AUTH_GENERIC_OAUTH_SCOPES: openid profile email
    GF_AUTH_GENERIC_OAUTH_AUTH_URL: https://auth.local/realms/homelab/protocol/openid-connect/auth
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL: https://auth.local/realms/homelab/protocol/openid-connect/token
    GF_AUTH_GENERIC_OAUTH_API_URL: https://auth.local/realms/homelab/protocol/openid-connect/userinfo
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP: true
    GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH: contains(groups[*], 'homelab-admins') && 'Admin' || 'Viewer'
```

#### 4.5 Traefik Dashboard

**Integration Method**: ForwardAuth middleware

**Configuration**:
```yaml
# docker-compose.yml (coreservices-homelab)
traefik:
  labels:
    - "traefik.http.routers.dashboard.middlewares=keycloak-auth@docker"
```

#### 4.5 HashiCorp Vault OIDC Integration

**Integration Method**: Vault OIDC Auth Method + Keycloak as OIDC Provider

**Architecture**:
```
User → Vault UI → Keycloak (OIDC) → Vault (Token) → User Access
```

**Benefits**:
- Single sign-on for Vault access
- Centralized user management in Keycloak
- Group-based policy mapping
- Audit trail through Keycloak
- No separate Vault user database needed

##### 4.5.1 Vault OIDC Auth Method Configuration

**Step 1: Enable OIDC Auth Method in Vault**

```bash
# Access Vault container
docker exec -it vault sh

# Set Vault address
export VAULT_ADDR='http://127.0.0.1:8200'

# Login with root token (initial setup)
vault login <root-token>

# Enable OIDC auth method
vault auth enable oidc

# Configure OIDC auth method
vault write auth/oidc/config \
    oidc_discovery_url="https://auth.local/realms/homelab" \
    oidc_client_id="vault" \
    oidc_client_secret="${KEYCLOAK_VAULT_CLIENT_SECRET}" \
    default_role="homelab-user"
```

**Step 2: Create Vault Roles Mapped to Keycloak Groups**

```bash
# Create role for admin users
vault write auth/oidc/role/homelab-admin \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.local/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="admin" \
    ttl=1h

# Create role for standard users
vault write auth/oidc/role/homelab-user \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.local/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="default" \
    ttl=1h
```

**Step 3: Create Group-Based Policies**

```bash
# Admin policy (full access)
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# Default policy (read-only for secrets)
vault policy write default - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
```

**Step 4: Map Keycloak Groups to Vault Policies**

```bash
# Create external group for Keycloak admins
vault write identity/group name="keycloak-admins" \
    policies="admin" \
    type="external"

# Get the group ID
ADMIN_GROUP_ID=$(vault read -field=id identity/group/name/keycloak-admins)

# Get OIDC accessor
OIDC_ACCESSOR=$(vault auth list -format=json | jq -r '.["oidc/"].accessor')

# Create group alias linking Keycloak group to Vault group
vault write identity/group-alias name="homelab-admins" \
    mount_accessor="${OIDC_ACCESSOR}" \
    canonical_id="${ADMIN_GROUP_ID}"
```

##### 4.5.2 Keycloak Client Configuration for Vault

**In Keycloak Admin Console** (`https://auth.local`):

1. **Create Vault Client**:
   - Client ID: `vault`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs:
     - `https://vault.local/ui/vault/auth/oidc/oidc/callback`
     - `http://localhost:8250/oidc/callback` (for CLI)
   - Base URL: `https://vault.local`

2. **Configure Client Scopes**:
   - Add `groups` scope to include group membership in tokens
   - Add `profile` and `email` scopes

3. **Create Group Mapper**:
   - Name: `groups`
   - Mapper Type: `Group Membership`
   - Token Claim Name: `groups`
   - Full group path: `OFF`
   - Add to ID token: `ON`
   - Add to access token: `ON`
   - Add to userinfo: `ON`

4. **Get Client Secret**:
   - Navigate to Credentials tab
   - Copy the secret to `KEYCLOAK_VAULT_CLIENT_SECRET` in `.env`

##### 4.5.3 Vault Configuration Update

Update Vault service in `coreservices-homelab/docker-compose.yml`:

```yaml
vault:
  image: hashicorp/vault:latest
  container_name: vault
  restart: unless-stopped
  depends_on:
    keycloak:
      condition: service_healthy
  cap_add:
    - IPC_LOCK
  security_opt:
    - no-new-privileges:true
  user: root
  ports:
    - "8083:8200"
  environment:
    VAULT_ADDR: http://0.0.0.0:8200
    VAULT_OIDC_CLIENT_SECRET: ${KEYCLOAK_VAULT_CLIENT_SECRET}
  volumes:
    - vault_data:/vault/data
    - vault_logs:/vault/logs
    - ./configs/vault/config.hcl:/vault/config/config.hcl:ro
    - ./configs/vault/oidc-setup.sh:/vault/scripts/oidc-setup.sh:ro
  command: >
    sh -ec '
    chown -R vault:vault /vault/data /vault/logs;
    exec su vault -s /bin/sh -c "vault server -config=/vault/config/config.hcl"
    '
  networks:
    - core-network
  labels:
    - "traefik.enable=true"
    - "traefik.docker.network=core-network"
    - "traefik.http.routers.vault.rule=Host(`vault.local`)"
    - "traefik.http.routers.vault.entrypoints=websecure"
    - "traefik.http.routers.vault.tls=true"
    - "traefik.http.services.vault.loadbalancer.server.port=8200"
  healthcheck:
    test: ["CMD-SHELL", "vault status -address=http://127.0.0.1:8200 >/dev/null 2>&1; code=$$?; [ $$code -eq 0 ] || [ $$code -eq 2 ]"]
    interval: 30s
    timeout: 10s
    retries: 5
    start_period: 10s
```

##### 4.5.4 Vault OIDC Setup Script

Create `coreservices-homelab/configs/vault/oidc-setup.sh`:

```bash
#!/bin/sh
# Vault OIDC Configuration Script
# Run after Vault is initialized and unsealed

set -e

export VAULT_ADDR='http://127.0.0.1:8200'

echo "Configuring Vault OIDC authentication..."

# Check if already configured
if vault auth list | grep -q oidc; then
    echo "OIDC auth method already enabled"
else
    echo "Enabling OIDC auth method..."
    vault auth enable oidc
fi

# Configure OIDC
echo "Configuring OIDC provider..."
vault write auth/oidc/config \
    oidc_discovery_url="https://auth.local/realms/homelab" \
    oidc_client_id="vault" \
    oidc_client_secret="${VAULT_OIDC_CLIENT_SECRET}" \
    default_role="homelab-user"

# Create admin role
echo "Creating admin role..."
vault write auth/oidc/role/homelab-admin \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.local/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="admin" \
    ttl=1h

# Create user role
echo "Creating user role..."
vault write auth/oidc/role/homelab-user \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.local/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="default" \
    ttl=1h

# Create policies
echo "Creating policies..."
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

vault policy write default - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

# Setup group mappings
echo "Setting up group mappings..."
vault write identity/group name="keycloak-admins" \
    policies="admin" \
    type="external"

ADMIN_GROUP_ID=$(vault read -field=id identity/group/name/keycloak-admins)
OIDC_ACCESSOR=$(vault auth list -format=json | jq -r '.["oidc/"].accessor')

vault write identity/group-alias name="homelab-admins" \
    mount_accessor="${OIDC_ACCESSOR}" \
    canonical_id="${ADMIN_GROUP_ID}"

echo "Vault OIDC configuration complete!"
```

##### 4.5.5 User Login Flow

**Web UI Login**:
1. Navigate to `https://vault.local`
2. Select "OIDC" as authentication method
3. Click "Sign in with OIDC Provider"
4. Redirected to Keycloak login
5. Enter Keycloak credentials
6. Redirected back to Vault with token

**CLI Login**:
```bash
vault login -method=oidc role=homelab-admin
# Opens browser for Keycloak authentication
```

##### 4.5.6 Vault as OIDC Identity Provider (Optional)

**Future Enhancement**: Configure Vault to act as an OIDC provider for other services

This creates a two-tier architecture:
- Keycloak → Primary IdP (user authentication)
- Vault → Secondary IdP (service-to-service auth, dynamic secrets)

**Use Cases**:
- Dynamic database credentials via OIDC
- Short-lived service tokens
- Certificate-based authentication
- Secret injection with OIDC validation

**Configuration** (for future implementation):
```bash
# Enable Vault identity secrets engine
vault secrets enable identity

# Configure OIDC provider
vault write identity/oidc/config \
    issuer="https://vault.local"

# Create OIDC client for services
vault write identity/oidc/client/my-service \
    redirect_uris="https://service.local/callback" \
    assignments="my-assignment" \
    key="default" \
    id_token_ttl=1h \
    access_token_ttl=1h
```

##### 4.5.7 Testing Vault OIDC Integration

**Test Checklist**:
- [ ] Vault OIDC auth method enabled
- [ ] Keycloak client configured with correct redirect URIs
- [ ] Admin user can login via OIDC
- [ ] Standard user can login via OIDC
- [ ] Group-based policies applied correctly
- [ ] Admin users have full Vault access
- [ ] Standard users have read-only access
- [ ] Token TTL and renewal working
- [ ] CLI login functional
- [ ] Logout clears session

**Troubleshooting**:
```bash
# Check OIDC configuration
vault read auth/oidc/config

# List OIDC roles
vault list auth/oidc/role

# Check user's token info
vault token lookup

# View audit logs
vault audit list
docker exec vault cat /vault/logs/audit.log
```


#### 4.6 Additional Services

**Services requiring ForwardAuth only**:
- SearXNG
- Ollama API
- MCPO
- PicoClaw
- AI Portal
- Core Portal

All receive middleware label:
```yaml
labels:
  - "traefik.http.routers.SERVICE.middlewares=keycloak-auth@docker"
```

### Phase 5: Migration & Deployment

#### 5.1 Pre-Deployment Checklist

- [ ] Backup existing service configurations
- [ ] Generate all required secrets and passwords
- [ ] Update `/etc/hosts` with `auth.local`
- [ ] Review resource allocations
- [ ] Test Keycloak container locally

#### 5.2 Deployment Sequence

1. **Deploy Keycloak infrastructure** (coreservices-homelab)
   ```bash
   cd coreservices-homelab
   docker-compose up -d keycloak-db keycloak
   ```

2. **Configure Keycloak realm**
   - Access https://auth.local
   - Login with admin credentials
   - Create `homelab` realm
   - Configure clients (manual or via script)
   - Create initial users and groups

3. **Deploy ForwardAuth service**
   ```bash
   docker-compose up -d traefik-forward-auth
   ```

4. **Update service configurations** (one at a time)
   - Start with non-critical service (e.g., SearXNG)
   - Add OIDC config or ForwardAuth middleware
   - Test authentication flow
   - Proceed to next service

5. **Update portal links**
   - Replace Logto references with Keycloak
   - Update environment variables
   - Rebuild portal containers

#### 5.3 Rollback Plan

If issues occur:
1. Remove ForwardAuth middleware labels from services
2. Revert service environment variables
3. Services remain accessible without authentication
4. Keycloak can stay running for troubleshooting

### Phase 6: Testing & Validation

#### 6.1 Keycloak Health Checks

- [ ] Keycloak admin console accessible at https://auth.local
- [ ] Database connection successful
- [ ] Realm configuration complete
- [ ] All clients registered

#### 6.2 Authentication Flow Tests

For each service:
- [ ] Unauthenticated access redirects to Keycloak
- [ ] Login with valid credentials succeeds
- [ ] User redirected back to service
- [ ] Session persists across page refreshes
- [ ] Logout clears session

#### 6.3 SSO Validation

- [ ] Login to one service
- [ ] Access another service without re-authentication
- [ ] Single logout terminates all sessions

#### 6.4 Authorization Tests

- [ ] Admin users can access all services
- [ ] Standard users have appropriate restrictions
- [ ] Group-based access control works (Grafana roles)

### Phase 7: Documentation & Maintenance

#### 7.1 User Documentation

Create `docs/keycloak-user-guide.md`:
- How to access services
- Password reset process
- Managing user profile
- Troubleshooting common issues

#### 7.2 Admin Documentation

Create `docs/keycloak-admin-guide.md`:
- Adding new users
- Creating new clients
- Managing groups and roles
- Backup and restore procedures
- Updating Keycloak

#### 7.3 Architecture Documentation

Update `ARCHITECTURE.md`:
- Add Keycloak architecture section
- Document authentication flow
- Explain ForwardAuth pattern
- List all protected services

## Security Considerations

### 1. Secrets Management

**Current Approach**: Environment variables in `.env`

**Recommendations**:
- Use strong, randomly generated passwords
- Store `.env` securely (not in git)
- Consider migrating to Vault for secret storage
- Rotate client secrets periodically

### 2. Network Security

- Keycloak only accessible via Traefik (HTTPS)
- Database not exposed to host network
- ForwardAuth validates all requests
- Session cookies marked secure and httpOnly

### 3. SSL/TLS

- All communication over HTTPS (Traefik handles)
- Self-signed certs for local development
- Can upgrade to Let's Encrypt for production

### 4. Session Management

- Configure appropriate session timeouts
- Implement refresh token rotation
- Enable remember-me functionality carefully
- Monitor active sessions

## Resource Requirements

### Keycloak Service

- **Memory**: 1-2GB (depends on user count)
- **CPU**: 0.5-1.0 cores
- **Storage**: ~500MB for application + database

### PostgreSQL (Keycloak DB)

- **Memory**: 512MB-1GB
- **CPU**: 0.25-0.5 cores
- **Storage**: ~100MB initial, grows with users

### ForwardAuth Service

- **Memory**: 50-100MB
- **CPU**: 0.1 cores
- **Storage**: Minimal (~20MB)

### Total Additional Resources

- **Memory**: ~2-3GB
- **CPU**: ~1-2 cores
- **Storage**: ~1GB

## Alternative Approaches Considered

### 1. Logto vs Keycloak

| Feature | Keycloak | Logto |
|---------|----------|-------|
| Maturity | Very mature (Red Hat) | Newer project |
| Features | Comprehensive | Modern, simpler |
| OIDC/SAML | Both | OIDC only |
| Community | Large | Growing |
| Complexity | Higher | Lower |

**Decision**: Keycloak for enterprise-grade features and maturity

### 2. Authentication Strategies

**Option A: Traefik ForwardAuth** (Chosen)
- Centralized authentication
- Works with any service
- Single point of control

**Option B: Per-Service OIDC**
- Native integration where supported
- More complex configuration
- Better for services with built-in SSO

**Decision**: Hybrid approach - ForwardAuth as default, native OIDC where beneficial

### 3. Database Strategy

**Option A: Dedicated PostgreSQL** (Chosen)
- Security isolation
- Independent lifecycle
- Easier backup/restore

**Option B: Shared PostgreSQL**
- Resource efficient
- Simpler management
- Single backup

**Decision**: Dedicated for production-grade security

## Future Enhancements

### Short Term (1-3 months)

- [ ] Implement MFA (TOTP/WebAuthn)
- [ ] Add social login providers (GitHub, Google)
- [ ] Configure email notifications
- [ ] Set up user self-registration

### Medium Term (3-6 months)

- [ ] Integrate with Vault for secret management
- [ ] Implement fine-grained authorization policies
- [ ] Add audit logging to Loki/Grafana
- [ ] Create automated user provisioning workflows (n8n)

### Long Term (6+ months)

- [ ] Implement SAML for legacy services
- [ ] Add identity federation (LDAP/AD)
- [ ] Create custom authentication flows
- [ ] Implement risk-based authentication

## Success Criteria

Implementation is successful when:

1. ✅ Keycloak is running and accessible at https://auth.local
2. ✅ All services protected with authentication
3. ✅ SSO works across all services
4. ✅ Users can login with single set of credentials
5. ✅ Admin can manage users and access via Keycloak UI
6. ✅ Documentation is complete and accurate
7. ✅ No degradation in service performance
8. ✅ Rollback plan tested and documented

## Timeline Estimate

- **Phase 1** (Infrastructure): 2-4 hours
- **Phase 2** (Realm Config): 2-3 hours
- **Phase 3** (ForwardAuth): 1-2 hours
- **Phase 4** (Service Integration): 4-6 hours
- **Phase 5** (Deployment): 2-3 hours
- **Phase 6** (Testing): 2-3 hours
- **Phase 7** (Documentation): 2-3 hours

**Total**: 15-24 hours of focused work

## Conclusion

This plan provides a comprehensive roadmap for implementing Keycloak as the centralized authentication and identity provider for the homelab infrastructure. The phased approach allows for incremental deployment and testing, minimizing risk while ensuring all services are properly protected.

The hybrid authentication strategy (ForwardAuth + native OIDC) provides flexibility while maintaining security. The architecture is designed to be maintainable, scalable, and aligned with industry best practices.