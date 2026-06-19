#!/opt/homebrew/bin/bash
set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# ---------------------------------------------------------------------------
# Service manifest
# ---------------------------------------------------------------------------
# Each service: build context (relative to PROJECT_ROOT), local image tag,
# GHCR repo name, primary GHCR tag, and optional extra GHCR tags.

declare -A BUILD_CONTEXT=(
  ["core-frontend"]="services/core-frontend"
  ["keycloak"]="services/keycloak"
)

declare -A LOCAL_TAG=(
  ["core-frontend"]="core-frontend:latest"
  ["keycloak"]="keycloak-optimized:26.2.5"
)

declare -A GHCR_REPO=(
  ["core-frontend"]="core-frontend"
  ["keycloak"]="keycloak-optimized"
)

declare -A GHCR_TAG=(
  ["core-frontend"]="latest"
  ["keycloak"]="26.2.5"
)

# Additional tags pushed after the primary (space-separated)
declare -A GHCR_EXTRA_TAGS=(
  ["core-frontend"]=""
  ["keycloak"]="latest"
)

ALL_SERVICES=(core-frontend keycloak)

# ---------------------------------------------------------------------------
# GHCR auth helpers
# ---------------------------------------------------------------------------

check_gh_cli() {
  if ! command -v gh &>/dev/null; then
    log_error "GitHub CLI (gh) is not installed"
    echo "Install it from: https://cli.github.com/"
    exit 1
  fi
}

check_gh_auth() {
  if ! gh auth status &>/dev/null; then
    log_error "Not authenticated with GitHub CLI"
    echo "Run: gh auth login"
    exit 1
  fi
}

get_github_username() {
  gh api user --jq '.login' 2>/dev/null || {
    log_error "Failed to get GitHub username"
    exit 1
  }
}

login_to_ghcr() {
  log_info "Logging in to GitHub Container Registry..."
  local gh_token
  gh_token=$(gh auth token)

  if [ -z "$gh_token" ]; then
    log_error "Failed to get GitHub token"
    exit 1
  fi

  echo "$gh_token" | docker login ghcr.io -u "$(get_github_username)" --password-stdin || {
    log_error "Failed to login to GHCR"
    log_warn "Ensure your token has write:packages scope:"
    echo "  gh auth refresh -h github.com -s write:packages"
    exit 1
  }
  log_info "Successfully logged in to GHCR"
}

# ---------------------------------------------------------------------------
# Build / push
# ---------------------------------------------------------------------------

build_service() {
  local svc="$1"
  local context="${PROJECT_ROOT}/${BUILD_CONTEXT[$svc]}"
  local tag="${LOCAL_TAG[$svc]}"

  log_info "Building ${svc} → ${tag}"
  docker build -t "$tag" "$context"
  log_info "Built ${tag}"
}

push_service() {
  local svc="$1"
  local local_tag="${LOCAL_TAG[$svc]}"
  local repo="${GHCR_REPO[$svc]}"
  local primary_tag="${GHCR_TAG[$svc]}"
  local username
  username=$(get_github_username)

  push_single() {
    local target="ghcr.io/${username}/${repo}:$1"
    log_info "Tagging ${local_tag} → ${target}"
    docker tag "$local_tag" "$target"
    log_info "Pushing ${target}"
    docker push "$target" || {
      log_error "Failed to push ${target}"
      log_warn "Common fixes:"
      echo "  gh auth refresh -h github.com -s write:packages"
      echo "  https://github.com/${username}?tab=packages"
      exit 1
    }
    log_info "Pushed ${target}"
  }

  push_single "$primary_tag"

  for extra in ${GHCR_EXTRA_TAGS[$svc]}; do
    push_single "$extra"
  done
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $0 [--service <name|all>] [--build-only | --push-only]

Build and push custom homelab service images to GHCR.

Options:
  --service <name>   Service to build/push: ${ALL_SERVICES[*]}, or "all" (default: all)
  --build-only       Only build, do not push
  --push-only        Only push (image must already be built)
  -h, --help         Show this help

Services:
$(for s in "${ALL_SERVICES[@]}"; do
  echo "  ${s}"
  echo "    build: ${BUILD_CONTEXT[$s]}"
  echo "    image: ${LOCAL_TAG[$s]}"
  echo "    ghcr:  ghcr.io/<user>/${GHCR_REPO[$s]}:${GHCR_TAG[$s]}"
  [ -n "${GHCR_EXTRA_TAGS[$s]}" ] && echo "           ghcr.io/<user>/${GHCR_REPO[$s]}:${GHCR_EXTRA_TAGS[$s]}"
done)

Examples:
  $0                              # build + push all services
  $0 --service core-frontend      # build + push core-frontend only
  $0 --service keycloak --build-only
  $0 --push-only                  # push all (assumes images already built)
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local services_to_run=("${ALL_SERVICES[@]}")
  local do_build=true
  local do_push=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --service)
        shift
        if [[ "$1" == "all" ]]; then
          services_to_run=("${ALL_SERVICES[@]}")
        elif [[ -v BUILD_CONTEXT["$1"] ]]; then
          services_to_run=("$1")
        else
          log_error "Unknown service: $1 (valid: ${ALL_SERVICES[*]}, all)"
          exit 1
        fi
        ;;
      --build-only) do_push=false ;;
      --push-only)  do_build=false ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
  done

  if $do_push; then
    check_gh_cli
    check_gh_auth
    login_to_ghcr
  fi

  for svc in "${services_to_run[@]}"; do
    log_info "--- ${svc} ---"
    $do_build && build_service "$svc"
    $do_push  && push_service  "$svc"
  done

  log_info "Done."
  if $do_push; then
    local username
    username=$(get_github_username)
    echo "View packages: https://github.com/${username}?tab=packages"
  fi
}

main "$@"
