# Core Services Testing Protocol

This document validates the `coreservices-homelab` stack only:
- `traefik`
- `vault`
- `logto`
- `grafana`
- `logto-db`

## 1) Preflight

```bash
cd /Users/rama/work/coreservices-homelab
docker-compose config
```

Expected: clean rendered config output.

## 2) Setup + Start

```bash
./scripts/setup.sh
./scripts/start.sh
docker-compose ps
```

Expected: all five services are `Up` (or `healthy` when healthchecks pass).

## 3) Service Checks

### `logto-db`

```bash
docker exec logto-db pg_isready -U "${LOGTO_DB_USER:-logto}" -d "${LOGTO_DB_NAME:-logto_db}"
```

### `vault`

```bash
curl -fsS http://127.0.0.1:8200/v1/sys/health
```

Note: Vault may report sealed before initialization/unseal.

### `logto`

```bash
docker-compose logs --tail=100 logto
curl -fsS http://127.0.0.1:3000/ || true
```

### `traefik`

```bash
docker-compose logs --tail=100 traefik
```

### `grafana`

```bash
curl -kfsS https://grafana.local/api/health
```

Expected: JSON containing a healthy database and service status.

Optional browser checks:
- `https://traefik.local`
- `https://auth.local`
- `https://grafana.local`

## 4) Backup / Restore Checks

```bash
./scripts/backup.sh
./scripts/restore.sh --dry-run
```

Expected:
- backup artifacts under `${BACKUP_LOCATION:-$HOME/coreservices-backups}`
- dry-run completes without data mutation

## 5) Stop Check

```bash
./scripts/stop.sh
docker-compose ps
```

Expected: stack is stopped/down.

## 6) Integration Spot Check with AI Stack

After core services are started, verify the shared network exists:

```bash
docker network inspect core-network >/dev/null && echo "core-network exists"
```

Then start `ai-stack-homelab`; routed services attached to `core-network` should be reachable through core Traefik.
