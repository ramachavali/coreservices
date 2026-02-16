# Core Services Installation Guide

## Scope

This guide installs only the core stack in `coreservices-homelab`:
- Traefik (edge routing)
- Vault (secrets)
- Logto (auth)
- logto-db (Postgres for Logto)

## Prerequisites

- Docker Engine + `docker-compose` CLI
- Host entries (or DNS) for local testing:
  - `traefik.local`
  - `auth.local`

## Install

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/setup.sh
docker-compose config
./scripts/start.sh
```

## Verify

```bash
docker-compose ps
docker-compose logs --tail=100 traefik logto vault logto-db
```

## Vault First-Time Init

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init -key-shares=1 -key-threshold=1 > vault-init.txt
vault operator unseal $(awk '/^Unseal Key 1:/ {print $4}' vault-init.txt)
```

## AI Stack Integration

1. Keep core services running.
2. In `ai-stack-homelab`, ensure routed services attach to external `core-network`.
3. Start AI stack:

```bash
cd /Users/rama/work/ai-stack-homelab
./scripts/start.sh
```

## Operations

```bash
./scripts/backup.sh
./scripts/restore.sh --dry-run
./scripts/stop.sh
```
