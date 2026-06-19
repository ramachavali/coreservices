# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`coreservices-homelab` is a Docker Compose stack that provides shared infrastructure for homelab services. It owns the `core-network` Docker bridge network, which application stacks (like `ai-stack-homelab`) attach to as an external network.

**Services:**
- **Traefik** — edge reverse proxy, TLS termination, routes by Docker labels, dashboard at `https://traefik.local`
- **Vault** — secrets manager with file backend, UI at `https://vault.local`
- **Grafana** — dashboards and metrics at `https://grafana.local`
- **Loki** — log aggregation backend (no UI, internal only)
- **Alloy** — Grafana telemetry pipeline, UI at `https://alloy.local`
- **core-frontend** — Flask portal app aggregating links/status, at `https://core.local`
- **registry** — local Docker registry at `https://registry.local:5001`

## Common Commands

```bash
# First-time setup (generates TLS certs, renders .env, creates data dirs)
./scripts/setup.sh

# Start all services (ordered: traefik+vault first, then rest)
./scripts/start.sh

# Stop all services
./scripts/stop.sh

# Restart
./scripts/restart.sh

# Validate compose config
docker-compose config

# Service logs
docker-compose logs -f <service>

# Status
docker-compose ps
```

## Vault Lifecycle

Vault requires manual init and unseal on first use (and after each restart since there's no auto-unseal):

```bash
# Initialize and unseal (saves init JSON to secrets/vault-init.json)
./scripts/vault-init.sh

# After vault-init, import .env secrets into Vault
python3 ./scripts/vault-import.py
```

The init file at `secrets/vault-init.json` contains the unseal key and root token — treat it as highly sensitive. The `secrets/` directory is chmod 700.

## PKI / TLS

`setup.sh` calls `scripts/pki-build.sh` to generate a local root CA and a wildcard leaf cert. Outputs:
- `pki/ca/rootCA.crt` — root CA (install in OS/browser trust store)
- `pki/certs/cert.pem` / `pki/certs/key.pem` — leaf cert (copied into `traefik_certs` volume)
- `pki/client/ca_bundle.crt` — CA bundle for clients

Re-running `setup.sh` reuses the existing root CA if `pki/ca/rootCA.key` exists. Delete those files to regenerate.

Covered SANs (defined in `setup.sh:setup_tls_certificates`): `traefik.local`, `grafana.local`, `core.local`, `alloy.local`, `vault.local`, `auth.local`, `keycloak.local`, and several AI stack hostnames.

## Environment / Secrets

- `scripts/.unrendered.env` — template with shell expressions; `setup.sh` renders it to `.env` and `.rendered.env`
- `.rendered.env` is the authoritative env file; `start.sh` passes it via `--env-file`
- Generated secrets use `openssl rand -hex` and are stored in `.env`/`.rendered.env`
- Keycloak client secrets (e.g. `KEYCLOAK_GRAFANA_CLIENT_SECRET`) start empty; `start.sh` populates them after realm init and prints them for manual entry

## Traefik Configuration

Traefik's static config (`configs/traefik/traefik.yml`) and dynamic config (`configs/traefik/dynamic.yml`) are actually mounted from `../ai-stack-homelab/configs/traefik/` — the Traefik config source of truth lives in the sibling repo. Services are discovered via Docker labels on `core-network`; `exposedByDefault: false` means every routed service needs `traefik.enable=true`.

## core-frontend

Python Flask app (`services/core-frontend/app.py`). Polls the Traefik API (`/api/http/routers` and `/api/http/services`) every 30s in a background thread and caches results. Routes:
- `GET /` — portal page with service links
- `GET /api/status` — JSON of polled Traefik service health
- `GET /health` — liveness probe

The published image is `ghcr.io/ramachavali/core-frontend:latest`. Rebuild and push with `scripts/push-to-ghcr.sh`.

## Keycloak (optional)

Keycloak is not in the current `docker-compose.yml` but `start.sh` detects it if added. When present, `start.sh` waits for it to be ready and then calls `init_keycloak_realm` to create the `homelab` realm, groups (`homelab-admins`, `homelab-users`, `homelab-monitoring`), and OIDC clients for all services.

## Backup / Restore

```bash
./scripts/backup.sh    # tarballs all compose volumes to $BACKUP_LOCATION (default: ~/coreservices-backups)
./scripts/restore.sh --dry-run
./scripts/restore.sh
```

## /etc/hosts

Required entries for local routing:
```
127.0.0.1 traefik.local auth.local grafana.local core.local vault.local registry.local alloy.local
```

## Network Contract with Application Stacks

This stack creates and owns `core-network`. Application stacks must declare it as external:

```yaml
networks:
  core-network:
    external: true
```

Services on `core-network` with `traefik.enable=true` labels are auto-discovered by Traefik. Start `coreservices-homelab` before starting any dependent application stack.
