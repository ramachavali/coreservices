# Core Services Architecture

This document describes the core-services cluster (Traefik, Vault, Logto + logto-db, Grafana) and how it operates standalone and integrates with application stacks (for example `ai-stack-homelab`).

## Overview

Core services provide central routing, authentication, logging, and secrets management for one or more application stacks running on the same Docker host or cluster.

Primary components:

- Traefik: Edge reverse proxy and router. Terminates TLS, exposes dashboard, routes requests to internal services by Docker network attachment and labels.
- Vault: Secrets manager for credentials, TLS keys, and dynamic secrets. Runs with a file backend by default (see `configs/vault/config.hcl`) — not recommended for production without TLS and auto-unseal.
- Logto: Authentication and identity provider. Requires a persistent database (`logto-db`).
- logto-db: Postgres backing Logto's data.
- Grafana: Metrics and dashboard UI for operational visibility.

All core services are attached to a Docker network named `core-network` which is meant to be created and owned by the core services docker-compose. Application stacks that need routing/auth should join the `core-network` (declared external in their compose) so Traefik and other core services can reach them.

## Standalone Behavior

1. Start core services in `coreservices-homelab`:

```bash
cd coreservices-homelab
docker-compose up -d
```

2. Traefik creates the `core-network` and listens on ports 80/443; it routes to services present on the same Docker network with appropriate labels.

3. Vault stores secrets in the `vault_data` volume (file backend). Initialize/unseal Vault manually the first time using Vault CLI:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init -key-shares=1 -key-threshold=1 > vault-init.txt
vault operator unseal $(awk '/^Unseal Key 1:/ {print $4}' vault-init.txt)
```

4. Logto uses `logto-db` for persistence and is exposed via Traefik using host rules (see compose labels). Configure `LOGTO_DATABASE_URL` if you prefer an external DB.

## Integration with Application Stacks

- Application stacks (for example `ai-stack-homelab`) should declare the `core-network` as an external network in their `docker-compose.yml` and attach services that need routing or authentication to that network.

Example snippet in application compose:

```yaml
networks:
  core-network:
    external: true

services:
  my-app:
    image: my-app
    networks:
      - core-network
    labels:
      - "traefik.http.routers.my-app.rule=Host(`my-app.local`)"
```

- With the above, Traefik (running in the core cluster) will discover `my-app` and route requests for `my-app.local` to it.

- For authentication, configure your app to use Logto's OIDC endpoints exposed by the `logto` service (e.g., `https://auth.local`). Vault may be used to store app secrets and TLS keys centrally.

## Security and Production Notes

- The provided Vault configuration uses a file backend and disables TLS in the listener for convenience. For production, enable TLS and use an auto-unseal mechanism (KMS/Auto Unseal or HA Raft storage).
- Run Traefik with secure certificate management (ACME or an internal PKI), and restrict dashboard access.
- Do not hardcode secrets in `.env` files — use Vault to inject secrets at runtime where possible.

## Backups and Recovery

Core services maintain important volumes:
- `vault_data` — Vault storage
- `traefik_certs` — TLS certificates
- `traefik_logs` — Traefik logs
- `logto_data` — Logto application data
- `logto_db_data` — Postgres data for Logto
- `grafana_data` — Grafana dashboards, users, and settings

Use `./scripts/backup.sh` and `./scripts/restore.sh` to manage backups for these volumes and the Logto database dump.

## Operational Tips

- Start core services before starting application stacks so `core-network` exists.
- Keep Traefik labels minimal and explicit to avoid accidental routing exposure.
- Consider running core services on a dedicated host or VM when exposing them to multiple application clusters.

For questions or help adapting core services for production, I can assist with TLS, auto-unseal, and hardened Vault configurations.
