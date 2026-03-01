#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


SECRET_KEY_PATTERN = re.compile(r"SECRET|PASSWORD|API_KEY")


def parse_args(project_root: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import secret-like keys from .rendered.env into Vault KV v2."
    )
    parser.add_argument(
        "--env-file",
        default=os.environ.get("ENV_FILE", str(project_root / ".rendered.env")),
        help="Source env file (default: ./.rendered.env)",
    )
    parser.add_argument(
        "--mount",
        default=os.environ.get("KV_MOUNT", "secret"),
        help="Vault KV mount name (default: secret)",
    )
    parser.add_argument(
        "--path",
        default=os.environ.get("KV_PATH", "core-services/env"),
        help="KV path inside mount (default: core-services/env)",
    )
    parser.add_argument(
        "--vault-addr",
        default=os.environ.get("VAULT_ADDR", "http://127.0.0.1:8200"),
        help="Vault address (default: http://127.0.0.1:8200)",
    )
    parser.add_argument(
        "--token",
        default=None,
        help="Vault token (overrides env/file lookup)",
    )
    parser.add_argument(
        "--container",
        default=os.environ.get("VAULT_CONTAINER", "vault"),
        help="Vault container name (default: vault)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be imported without writing",
    )
    return parser.parse_args()


def run_command(cmd: list[str], *, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, capture_output=True, text=True, env=env)


def resolve_vault_token(project_root: Path, explicit_token: str | None) -> str:
    if explicit_token:
        return explicit_token

    env_token = os.environ.get("VAULT_TOKEN", "")
    if env_token:
        return env_token

    init_file = project_root / "secrets/vault-init.json"
    if init_file.exists():
        try:
            data = json.loads(init_file.read_text(encoding="utf-8"))
            return str(data.get("root_token", ""))
        except json.JSONDecodeError:
            return ""

    return ""


def parse_secret_env(env_file: Path) -> dict[str, str]:
    secrets: dict[str, str] = {}
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if len(value) >= 2 and ((value[0] == '"' and value[-1] == '"') or (value[0] == "'" and value[-1] == "'")):
            value = value[1:-1]

        if SECRET_KEY_PATTERN.search(key):
            secrets[key] = value

    return secrets


def ensure_container_running(container_name: str) -> None:
    result = run_command(["docker", "ps", "--format", "{{.Names}}"], check=False)
    names = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    if container_name not in names:
        print(f"❌ Vault container '{container_name}' is not running", file=sys.stderr)
        print("Start core services first: ./scripts/start.sh", file=sys.stderr)
        sys.exit(1)


def vault_env(vault_addr: str, vault_token: str) -> dict[str, str]:
    env = os.environ.copy()
    env["VAULT_ADDR"] = vault_addr
    env["VAULT_TOKEN"] = vault_token
    return env


def ensure_kv_v2_mount(container_name: str, mount: str, env: dict[str, str]) -> None:
    result = run_command(
        ["docker", "exec", "-e", f"VAULT_ADDR={env['VAULT_ADDR']}", "-e", f"VAULT_TOKEN={env['VAULT_TOKEN']}", container_name, "vault", "secrets", "list", "-format=json"],
        check=False,
    )
    if result.returncode != 0:
        print("❌ Unable to list Vault secrets engines", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
        sys.exit(1)

    try:
        mounts = json.loads(result.stdout)
    except json.JSONDecodeError:
        print("❌ Failed to parse Vault secrets list output", file=sys.stderr)
        sys.exit(1)

    mount_key = mount.rstrip("/") + "/"
    entry = mounts.get(mount_key)
    if not entry or entry.get("type") != "kv" or entry.get("options", {}).get("version") != "2":
        print(f"❌ Mount '{mount}' is not an existing KV v2 engine", file=sys.stderr)
        print(f"Enable one first (example): vault secrets enable -path={mount} kv-v2", file=sys.stderr)
        sys.exit(1)


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    os.chdir(project_root)

    args = parse_args(project_root)
    env_file = Path(args.env_file)

    if not env_file.exists():
        print(f"❌ Env file not found: {env_file}", file=sys.stderr)
        return 1

    ensure_container_running(args.container)

    token = resolve_vault_token(project_root, args.token)
    if not token and not args.dry_run:
        print("❌ Vault token not found. Provide --token or set VAULT_TOKEN.", file=sys.stderr)
        return 1

    secrets = parse_secret_env(env_file)
    if not secrets:
        print(f"⚠️ No keys matching SECRET/PASSWORD/API_KEY found in {env_file}")
        return 0

    if args.dry_run:
        print(f"Dry run: would import {len(secrets)} keys into {args.mount}/{args.path}")
        for key in sorted(secrets.keys()):
            print(f"  - {key}")
        return 0

    venv = vault_env(args.vault_addr, token)
    status_cmd = [
        "docker",
        "exec",
        "-e",
        f"VAULT_ADDR={venv['VAULT_ADDR']}",
        "-e",
        f"VAULT_TOKEN={venv['VAULT_TOKEN']}",
        args.container,
        "vault",
        "status",
    ]
    status_result = run_command(status_cmd, check=False)
    if status_result.returncode != 0:
        print(f"❌ Unable to reach/unlock Vault at {args.vault_addr} with provided token", file=sys.stderr)
        print(status_result.stderr.strip(), file=sys.stderr)
        return 1

    ensure_kv_v2_mount(args.container, args.mount, venv)

    print(f"Importing {len(secrets)} keys to Vault KV v2 path {args.mount}/{args.path}...")
    for key, value in secrets.items():
        patch_cmd = [
            "docker",
            "exec",
            "-e",
            f"VAULT_ADDR={venv['VAULT_ADDR']}",
            "-e",
            f"VAULT_TOKEN={venv['VAULT_TOKEN']}",
            args.container,
            "vault",
            "kv",
            "patch",
            f"-mount={args.mount}",
            args.path,
            f"{key}={value}",
        ]
        result = run_command(patch_cmd, check=False)
        if result.returncode != 0:
            print(f"❌ Failed importing key: {key}", file=sys.stderr)
            print(result.stderr.strip(), file=sys.stderr)
            return 1

    print("✅ Vault import complete")
    print(f"Path: {args.mount}/{args.path}")
    print(f"Imported keys: {len(secrets)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())