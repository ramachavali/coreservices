# Core Services Stack

Shared infrastructure stack for local routing, auth, and secrets.

## Includes

- Traefik (TLS + reverse proxy)
- Vault
- Grafana
- Core frontend (`core.local`)

This stack owns Docker network `core-network`. Other stacks attach to it to use shared routing and TLS.

## Quick Start

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/setup.sh
./scripts/start.sh
```

## Hostnames

Add to `/etc/hosts`:

```text
127.0.0.1 traefik.local auth.local grafana.local core.local vault.local
```

## URLs

- https://traefik.local
- https://auth.local
- https://grafana.local
- https://core.local
- https://vault.local

## Operations

```bash
./scripts/start.sh
./scripts/stop.sh
./scripts/restart.sh
docker-compose logs -f <service>
docker-compose ps
```

## Config Source of Truth

- `docker-compose.yml`
- `scripts/.unrendered.env`
- `configs/vault/config.hcl`
- `configs/traefik/traefik.yml`
- `configs/traefik/dynamic.yml`

## Notes

- `setup.sh` also generates and installs local TLS certs into `traefik_certs`.
- Vault still requires init/unseal before use.