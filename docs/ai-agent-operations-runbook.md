# AI Agent Operations Runbook (AI Stack + Core Services)

This runbook instructs an AI agent how to operate both stacks consistently:

- Application stack: `/Users/rama/work/ai-stack-homelab`
- Core stack: `/Users/rama/work/coreservices-homelab`

## Dependency Rules

- `ai-stack-homelab` depends on core networking and routing (`core-network`, Traefik/TLS from core).
- Because of dependencies:
  - **Setup/Start order:** Core first, then Application.
  - **Stop/Backup/Cleanup order:** Application first, then Core (core services last).

## Global Execution Rules (for AI agent)

1. Run scripts from their repo root directories only.
2. Do not run cross-stack lifecycle operations in parallel.
3. Stop on first critical failure and report exact command + output.
4. Prefer project scripts over ad-hoc Docker commands.
5. If `.env` and `.rendered.env` were removed by cleanup, run `setup.sh` before `start.sh`.

---

## 1) Setup (cold/fresh state)

> Required before first startup, or after cleanup removed env/volumes.

### Core setup (first)

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/setup.sh
```

### Application setup (second)

```bash
cd /Users/rama/work/ai-stack-homelab
./scripts/setup.sh
```

---

## 2) Start

> Bring up core before app so dependency network/routing is available.

### Start core (first)

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/start.sh
```

### Start app (second)

```bash
cd /Users/rama/work/ai-stack-homelab
./scripts/start.sh
```

### Post-start checks

```bash
docker compose -f /Users/rama/work/coreservices-homelab/docker-compose.yml ps
docker compose -f /Users/rama/work/ai-stack-homelab/docker-compose.yml --profile picoclaw ps
```

---

## 3) Stop

> Application first, core last.

### Stop app (first)

```bash
cd /Users/rama/work/ai-stack-homelab
./scripts/stop.sh
```

### Stop core (last)

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/stop.sh
```

If graceful stop hangs, rerun with force:

```bash
./scripts/stop.sh --force
```

---

## 4) Backup

> Backup application first, then core.

### Backup app (first)

```bash
cd /Users/rama/work/ai-stack-homelab
./scripts/backup.sh
```

### Backup core (last)

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/backup.sh
```

Notes:
- If consistency is critical, stop app before backup.
- Keep backup destination variables configured in env files.

---

## 5) Cleanup

> Cleanup is destructive. Always application first, core last.

### Cleanup app (first)

```bash
cd /Users/rama/work/ai-stack-homelab
printf 'yes\n' | ./scripts/cleanup.sh
```

### Cleanup core (last)

```bash
cd /Users/rama/work/coreservices-homelab
printf 'y\n' | ./scripts/cleanup.sh
```

After cleanup, both stacks usually require `setup.sh` again before `start.sh`.

---

## Quick Operational Matrix

- **Setup:** Core -> App
- **Start:** Core -> App
- **Stop:** App -> Core
- **Backup:** App -> Core
- **Cleanup:** App -> Core

This order keeps dependency handling consistent and avoids breaking application startup expectations.
