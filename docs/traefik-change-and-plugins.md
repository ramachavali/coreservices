# Traefik Change Pickup and Plugin Setup

This runbook explains what changes Traefik picks up automatically and what requires a restart.

## Change Pickup Matrix

- Docker label changes on running services:
  - Picked up automatically by Docker provider.
  - No Traefik restart required.
- New/removed containers with `traefik.enable=true`:
  - Picked up automatically.
  - No Traefik restart required.
- `configs/traefik/dynamic.yml` changes:
  - Picked up automatically by file provider (`watch: true`).
  - No Traefik restart required.
- `configs/traefik/traefik.yml` changes:
  - Static configuration.
  - Requires Traefik restart.

## Plugin Setup (Local Development)

1. Declare plugin in `configs/traefik/traefik.yml` under `experimental.plugins`.
2. Restart Traefik to load plugin code.
3. Define middleware instance in `configs/traefik/dynamic.yml`.
4. Attach middleware to one router first.
5. Verify Traefik logs and route behavior.
6. Roll out middleware to additional routers.

## Example Skeleton

```yaml
# traefik.yml (static)
experimental:
  plugins:
    myplugin:
      moduleName: github.com/example/traefik-plugin-example
      version: v0.1.0
```

```yaml
# dynamic.yml (dynamic)
http:
  middlewares:
    myplugin-mw:
      plugin:
        myplugin:
          enabled: true
```

```yaml
# docker-compose service labels
labels:
  - "traefik.http.routers.my-service.middlewares=myplugin-mw@file"
```

## Recommended Validation

- `docker-compose logs --tail=200 traefik`
- `curl -k https://traefik.local`
- `curl -k https://<router-host>.local`
