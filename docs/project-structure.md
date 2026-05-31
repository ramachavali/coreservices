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
│   ├── traefik/
│   └── vault/
│       └── config.hcl
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

- `docker-compose.yml`: defines Traefik, Vault, Grafana, and core frontend.
- `scripts/.unrendered.env`: template with generated secrets.
- `scripts/setup.sh`: renders `.env`/`.rendered.env` and prepares local dirs.
- `scripts/start.sh`: validates env and starts services.
- `scripts/stop.sh`: graceful shutdown and optional volume removal.
- `scripts/backup.sh`: backups for `vault_data` and `traefik_*`.
- `scripts/restore.sh`: restore path with optional dry-run.

## Network Contract

- Core stack owns Docker network `core-network`.
- External application stacks attach routed services to external `core-network`.

## Volumes

- `traefik_certs`
- `traefik_logs`
- `vault_data`
- `grafana_data`
