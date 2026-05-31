#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}ℹ️  $1${NC}"
}

log_warn() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

check_gh_cli() {
  if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is not installed"
    echo "Install it from: https://cli.github.com/"
    exit 1
  fi
}

check_gh_auth() {
  if ! gh auth status &> /dev/null; then
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

  echo "$gh_token" | docker login ghcr.io -u "$(get_github_username)" --password-stdin

  if [ $? -eq 0 ]; then
    log_info "Successfully logged in to GHCR"
  else
    log_error "Failed to login to GHCR"
    log_warn "If authentication failed, ensure your token has the required scopes:"
    echo "  • write:packages"
    echo "  • read:packages"
    echo "  • delete:packages (optional)"
    echo "To refresh your GitHub CLI authentication with correct scopes:"
    echo "  gh auth refresh -h github.com -s write:packages"
    exit 1
  fi
}

push_image() {
  local source_image="$1"
  local target_repo="$2"
  local tag="${3:-latest}"

  local username
  username=$(get_github_username)

  local target_image="ghcr.io/${username}/${target_repo}:${tag}"

  log_info "Tagging image: ${source_image} -> ${target_image}"
  docker tag "$source_image" "$target_image"

  log_info "Pushing image to GHCR: ${target_image}"

  if docker push "$target_image" 2>&1; then
    log_info "Successfully pushed ${target_image}"
  else
    local exit_code=$?
    log_error "Failed to push ${target_image}"
    log_warn "Common issues and solutions:"
    echo "1. Token permissions issue:"
    echo "   Run: gh auth refresh -h github.com -s write:packages"
    echo "2. Package doesn't exist yet:"
    echo "   • First push creates the package"
    echo "   • Make sure package name is valid (lowercase, alphanumeric, hyphens)"
    echo "   • Check: https://github.com/$(get_github_username)?tab=packages"
    echo "3. Package visibility:"
    echo "   • New packages are private by default"
    echo "   • Change to public: Package Settings → Change visibility"
    echo "4. Repository permissions:"
    echo "   • Ensure you have write access to the repository"
    echo "   • For organization repos, check organization package settings"
    exit $exit_code
  fi
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS] SOURCE_IMAGE TARGET_REPO [TAG]

Push a Docker image to GitHub Container Registry (GHCR).

Arguments:
  SOURCE_IMAGE    Local Docker image name (e.g., myapp:latest)
  TARGET_REPO     Target repository name on GHCR (e.g., myapp)
  TAG             Image tag (default: latest)

Options:
  -h, --help      Show this help message

Examples:
  # Push local image to GHCR
  $0 myapp:latest myapp

  # Push with specific tag
  $0 myapp:v1.0.0 myapp v1.0.0

  # Push from local registry
  $0 localhost:5000/signal-cli-rest-api:latest signal-cli-rest-api

Environment:
  The script uses 'gh auth token' to authenticate with GHCR.
  Make sure you're logged in with: gh auth login

Required GitHub Token Scopes:
  • write:packages - Required to push images
  • read:packages - Required to pull images
  • delete:packages - Optional, for deleting packages

Setup:
  1. Login to GitHub CLI:
     gh auth login

  2. Refresh token with required scopes:
     gh auth refresh -h github.com -s write:packages

  3. Verify authentication:
     gh auth status

Troubleshooting:
  If you get "permission_denied" or "token does not match expected scopes":
  • Run: gh auth refresh -h github.com -s write:packages
  • This will request a new token with the correct permissions

EOF
}

main() {
  if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
  fi

  if [ $# -lt 2 ]; then
    log_error "Missing required arguments"
    usage
    exit 1
  fi

  local source_image="$1"
  local target_repo="$2"
  local tag="${3:-latest}"

  if ! docker image inspect "$source_image" &> /dev/null; then
    log_error "Source image not found: ${source_image}"
    echo "Available images:"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    exit 1
  fi

  check_gh_cli
  check_gh_auth

  login_to_ghcr
  push_image "$source_image" "$target_repo" "$tag"

  log_info "✅ Image successfully pushed to GHCR"
  echo "View your image at: https://github.com/$(get_github_username)?tab=packages"
  echo "Pull command: docker pull ghcr.io/$(get_github_username)/${target_repo}:${tag}"
}

main "$@"
