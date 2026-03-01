#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

CORE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_BUNDLE="${CORE_ROOT}/pki/client/ca_bundle.crt"

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ docker not found"
  exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1; then
  echo "❌ docker-compose not found"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "❌ curl not found"
  exit 1
fi

if [ ! -f "$CA_BUNDLE" ]; then
  echo "❌ CA bundle not found: $CA_BUNDLE"
  exit 1
fi

failures=0

run_endpoint_check() {
  local host="$1"
  local path="$2"
  local expected_codes_csv="$3"

  local out code verify
  out="$(curl --silent --show-error --output /dev/null --write-out '%{http_code} %{ssl_verify_result}' --cacert "$CA_BUNDLE" --resolve "${host}:443:127.0.0.1" "https://${host}${path}" 2>&1 || true)"
  code="$(echo "$out" | awk '{print $1}')"
  verify="$(echo "$out" | awk '{print $2}')"

  if [ "$verify" = "0" ] && [[ ",$expected_codes_csv," == *",$code,"* ]]; then
    echo "✅ [${code}/${verify}] https://${host}${path}"
  else
    echo "❌ [${out}] https://${host}${path}"
    failures=$((failures + 1))
  fi
}

run_core_stack_health() {
  echo ""
  echo "===== CORE CONTAINER HEALTH ====="
  cd "$CORE_ROOT"

  local service cid status health
  while IFS= read -r service; do
    cid="$(docker-compose ps -q "$service" 2>/dev/null || true)"
    if [ -z "$cid" ]; then
      echo "❌ [missing] ${service}"
      failures=$((failures + 1))
      continue
    fi

    status="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo unknown)"

    if [ "$status" = "running" ] && { [ "$health" = "healthy" ] || [ "$health" = "none" ]; }; then
      echo "✅ [${status}/${health}] ${service}"
    else
      echo "❌ [${status}/${health}] ${service}"
      failures=$((failures + 1))
    fi
  done < <(docker-compose config --services)
}

echo "===== CORE HTTPS/TLS ENDPOINT CHECKS ====="
run_endpoint_check "traefik.local" "/" "200,302,404"
run_endpoint_check "vault.local" "/v1/sys/health" "200"
run_endpoint_check "auth.local" "/status" "200"
run_endpoint_check "grafana.local" "/api/health" "200"
run_endpoint_check "core.local" "/health" "200"
run_endpoint_check "alloy.local" "/" "200"

run_core_stack_health

echo ""
if [ "$failures" -gt 0 ]; then
  echo "❌ Core healthcheck completed with ${failures} failure(s)."
  exit 1
fi

echo "✅ Core healthcheck passed with zero failures."
