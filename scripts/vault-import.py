#!/usr/bin/env python3
"""Import all env vars from .rendered.env into Vault KV v2."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def parse_args(project_root: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import all env vars from .rendered.env into Vault KV v2."
    )
    parser.add_argument(
        "--env-file",
        default=os.environ.get("ENV_FILE", str(project_root / ".rendered.env")),
    )
    parser.add_argument("--mount", default=os.environ.get("KV_MOUNT", "secret"))
    parser.add_argument("--path", default=os.environ.get("KV_PATH", "core-services/env"))
    parser.add_argument("--vault-addr", default=os.environ.get("VAULT_ADDR", "http://127.0.0.1:8200"))
    parser.add_argument("--token", default=None)
    parser.add_argument("--container", default=os.environ.get("VAULT_CONTAINER", "vault"))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def run_command(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def run_vault(container: str, vault_addr: str, vault_token: str, *args: str) -> subprocess.CompletedProcess[str]:
    return run_command(
        ["docker", "exec",
         "-e", f"VAULT_ADDR={vault_addr}",
         "-e", f"VAULT_TOKEN={vault_token}",
         container, "vault", *args],
        check=False,
    )


def resolve_vault_token(project_root: Path, explicit_token: str | None) -> str:
    if explicit_token:
        return explicit_token
    if token := os.environ.get("VAULT_TOKEN", ""):
        return token
    init_file = project_root / "secrets/vault-init.json"
    if init_file.exists():
        try:
            data = json.loads(init_file.read_text(encoding="utf-8"))
            return str(data.get("root_token", ""))
        except json.JSONDecodeError:
            pass
    return ""


def parse_env_file(env_file: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        if value:
            result[key] = value
    return result


def ensure_container_running(container: str) -> None:
    result = run_command(["docker", "ps", "--format", "{{.Names}}"], check=False)
    if container not in {line.strip() for line in result.stdout.splitlines()}:
        print(f"❌ Container '{container}' is not running. Start core services first.", file=sys.stderr)
        sys.exit(1)


def ensure_kv_v2_mount(container: str, vault_addr: str, vault_token: str, mount: str) -> None:
    result = run_vault(container, vault_addr, vault_token, "secrets", "list", "-format=json")
    if result.returncode != 0:
        print("❌ Unable to list Vault secrets engines", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
        sys.exit(1)
    try:
        mounts = json.loads(result.stdout)
    except json.JSONDecodeError:
        print("❌ Failed to parse Vault secrets list", file=sys.stderr)
        sys.exit(1)
    entry = mounts.get(f"{mount.rstrip('/')}/")
    if not entry or entry.get("type") != "kv" or entry.get("options", {}).get("version") != "2":
        print(f"❌ '{mount}' is not a KV v2 engine.", file=sys.stderr)
        print(f"   Enable with: vault secrets enable -path={mount} kv-v2", file=sys.stderr)
        sys.exit(1)


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    args = parse_args(project_root)
    env_file = Path(args.env_file)

    if not env_file.exists():
        print(f"❌ Env file not found: {env_file}", file=sys.stderr)
        return 1

    secrets = parse_env_file(env_file)
    if not secrets:
        print(f"⚠️  No entries found in {env_file}")
        return 0

    if args.dry_run:
        print(f"Dry run — would write {len(secrets)} keys to {args.mount}/{args.path}:")
        for key in sorted(secrets):
            print(f"  {key}")
        return 0

    ensure_container_running(args.container)

    token = resolve_vault_token(project_root, args.token)
    if not token:
        print("❌ Vault token not found. Provide --token or set VAULT_TOKEN.", file=sys.stderr)
        return 1

    status = run_vault(args.container, args.vault_addr, token, "status")
    if status.returncode != 0:
        print(f"❌ Vault is sealed or unreachable at {args.vault_addr}", file=sys.stderr)
        print(status.stderr.strip(), file=sys.stderr)
        return 1

    ensure_kv_v2_mount(args.container, args.vault_addr, token, args.mount)

    kv_pairs = [f"{k}={v}" for k, v in secrets.items()]
    result = run_vault(
        args.container, args.vault_addr, token,
        "kv", "put", f"-mount={args.mount}", args.path, *kv_pairs,
    )
    if result.returncode != 0:
        print("❌ Vault write failed", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
        return 1

    print(f"✅ Wrote {len(secrets)} keys to {args.mount}/{args.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
