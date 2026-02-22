# Core Services Project Structure

```
coreservices-homelab/
├── docker-compose.yml
├── README.md
├── TESTING.md
├── docs/
│   ├── architecture.md
│   ├── installation-guide.md
│   └── project-structure.md
├── configs/
│   ├── traefik/            # (referenced from ai-stack config path currently)
│   ├── vault/
│   │   └── config.hcl
│   └── logto/
│       └── README.md
└── scripts/
    ├── .unrendered.env
    ├── setup.sh
    ├── start.sh
    ├── stop.sh
    ├── backup.sh
    ├── restore.sh
    └── cleanup.sh
```

## Responsibilities

- `docker-compose.yml`: defines Traefik, Vault, Logto, `logto-db`, Grafana, and core frontend.
- `scripts/.unrendered.env`: template with generated secrets for Logto and DB.
- `scripts/setup.sh`: renders `.env`/`.rendered.env` and prepares local dirs.
- `scripts/start.sh`: validates env, starts services, verifies `logto-db` readiness.
- `scripts/stop.sh`: graceful shutdown and optional volume removal.
- `scripts/backup.sh`: backups for `vault_data`, `traefik_*`, `logto_data`, and DB dump.
- `scripts/restore.sh`: restore path with optional dry-run.

## Network Contract

- Core stack owns Docker network `core-network`.
- External stacks (e.g., `ai-stack-homelab`) attach routed services to external `core-network`.

## Volumes

- `traefik_certs`
- `traefik_logs`
- `vault_data`
- `logto_data`
- `logto_db_data_pg18`
- `grafana_data`
