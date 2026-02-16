Traefik core services

This folder contains the Traefik reverse-proxy which acts as the centralized routing/auth/log/secrets entrypoint for app stacks.

Quick start

1. Start the core Traefik stack (creates the `core-network` Docker network):

```bash
cd coreservices-homelab
docker-compose up -d
```

Add host entries for local access:

```bash
sudo sh -c 'echo "127.0.0.1 traefik.local auth.local core.local" >> /etc/hosts'
```

2. Start the AI stack (which depends on the external `core-network` Docker network):

```bash
cd ../ai-stack-homelab
docker-compose up -d
```

Notes

- Traefik reads configuration from `../ai-stack-homelab/configs/traefik/traefik.yml` and `dynamic.yml`.
- Traefik creates and owns the Docker network named `core-network` and volumes `traefik_certs` and `traefik_logs`.
- The AI stack services should attach to an external network named `core-network` so Traefik can route to them.

Added services

- `vault`: HashiCorp Vault (file backend). After `docker-compose up` you must initialize and unseal Vault. Example quick-init (one-time):

```bash
# initialize
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init -key-shares=1 -key-threshold=1 > vault-init.txt
# unseal
vault operator unseal $(awk '/^Unseal Key 1:/ {print $4}' vault-init.txt)
# extract root token
grep 'Initial Root Token:' -A0 vault-init.txt || true
```

- `logto`: Logto auth server (image `logto/logto:latest`). Provide `LOGTO_DATABASE_URL` and other env vars in your `.env` or orchestrator. See `configs/logto/README.md`.

- `core-frontend`: simple Flask UI without login at `https://core.local`, with quick links to Vault UI and Logto UI.

- `logto-db`: Postgres instance for Logto (created by this compose). Credentials are sourced from env (`LOGTO_DB_USER`, `LOGTO_DB_PASSWORD`, `LOGTO_DB_NAME`).

```
LOGTO_DB_USER=logto
LOGTO_DB_PASSWORD=<generated>
LOGTO_DB_NAME=logto_db
```

`LOGTO_DATABASE_URL` is built from those values in `scripts/.unrendered.env` during `./scripts/setup.sh`.

Security notes

- Vault is configured with a file backend in `configs/vault/config.hcl`. For production you should enable TLS and a secure storage backend or auto-unseal mechanism.
- Logto requires a persistent database (Postgres/MySQL) and secure app secrets before exposing to the internet.