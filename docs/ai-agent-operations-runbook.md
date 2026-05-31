# Core Services Operations Runbook

This runbook instructs an AI agent how to operate the core services stack.

- Core stack: `/Users/rama/work/coreservices-homelab`

## Global Execution Rules (for AI agent)

1. Run scripts from the repo root directory only.
2. Stop on first critical failure and report exact command + output.
3. Prefer project scripts over ad-hoc Docker commands.
4. If `.env` and `.rendered.env` were removed by cleanup, run `setup.sh` before `start.sh`.

---

## 1) Setup (cold/fresh state)

> Required before first startup, or after cleanup removed env/volumes.

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/setup.sh
```

---

## 2) Start

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/start.sh
```

### Post-start check

```bash
docker compose -f /Users/rama/work/coreservices-homelab/docker-compose.yml ps
```

---

## 3) Stop

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

```bash
cd /Users/rama/work/coreservices-homelab
./scripts/backup.sh
```

Notes:
- Keep backup destination variables configured in env files.

---

## 5) Cleanup

> Cleanup is destructive.

```bash
cd /Users/rama/work/coreservices-homelab
printf 'y\n' | ./scripts/cleanup.sh
```

After cleanup, run `setup.sh` again before `start.sh`.
