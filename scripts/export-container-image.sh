#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
  echo -e "${BLUE}▶️  $1${NC}"
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS] CONTAINER_NAME IMAGE_NAME[:TAG]

Export a running Docker container as a custom image.

Arguments:
  CONTAINER_NAME  Name or ID of the running container
  IMAGE_NAME      Name for the new image (can include tag, default: latest)

Options:
  -m, --message     Commit message describing the changes
  -a, --author      Author of the commit (default: current user)
  -p, --pause       Pause container during commit (default: true)
  --no-pause        Don't pause container during commit
  -d, --with-data   Include volume data in export (creates tarball with image + data)
  -o, --output-dir  Output directory for data export (default: ./exports)
  -h, --help        Show this help message

Examples:
  # Export container with default tag
  $0 vault my-custom-vault

  # Export with specific tag
  $0 vault my-custom-vault:v1.0.0

  # Export with commit message
  $0 -m "Added custom configuration" vault my-custom-vault:configured

  # Export without pausing (for containers that can't be paused)
  $0 --no-pause vault my-custom-vault:latest

  # Export with volume data included
  $0 --with-data vault my-custom-vault:v1.0.0

  # Export with data to specific directory
  $0 --with-data --output-dir ./backups vault my-custom-vault:v1.0.0

  # Export and push to GHCR in one go
  $0 vault my-custom-vault:v1.0.0 && ./scripts/push-to-ghcr.sh my-custom-vault:v1.0.0 my-custom-vault v1.0.0

Common Workflow:
  1. Make changes to a running container
  2. Export container as custom image: $0 container-name my-image:tag
  3. Push to GHCR: ./scripts/push-to-ghcr.sh my-image:tag repo-name tag
  4. Use in docker-compose or pull on other systems

EOF
}

list_containers() {
  log_info "Running containers:"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
}

get_container_volumes() {
  local container_name="$1"
  docker inspect "$container_name" --format='{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.Type}}{{"\n"}}{{end}}' 2>/dev/null || echo ""
}

export_volume_data() {
  local container_name="$1"
  local output_dir="$2"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local export_name="${container_name}_data_${timestamp}"
  local export_path="${output_dir}/${export_name}"

  log_step "Exporting volume data for container: ${container_name}"

  mkdir -p "$export_path"

  local volumes
  volumes=$(get_container_volumes "$container_name")

  if [ -z "$volumes" ]; then
    log_warn "No volumes found for container ${container_name}"
    return 0
  fi

  log_info "Found volumes:"
  echo "$volumes" | while IFS=: read -r source dest type; do
    if [ -n "$source" ]; then
      echo "  • ${dest} (${type}): ${source}"
    fi
  done

  local volume_count=0
  echo "$volumes" | while IFS=: read -r source dest type; do
    if [ -n "$source" ] && [ -d "$source" ]; then
      volume_count=$((volume_count + 1))
      local volume_name=$(basename "$dest" | tr '/' '_')
      local tar_file="${export_path}/volume_${volume_name}.tar.gz"

      log_step "Backing up volume: ${dest}"
      log_info "Source: ${source}"
      log_info "Archive: ${tar_file}"

      tar -czf "$tar_file" -C "$source" . 2>/dev/null || {
        log_warn "Failed to backup ${dest}, skipping..."
        continue
      }

      log_info "✅ Backed up ${dest}"
    fi
  done
  
  log_info "✅ Volume data exported to: ${export_path}"
  log_info "To restore: cd ${export_path} && ./restore-volume-data.sh <container_name>"

  echo "$export_path"
}

export_container() {
  local container_name="$1"
  local image_name="$2"
  local message="${3:-Exported from container ${container_name}}"
  local author="${4:-$(whoami)}"
  local pause="${5:-true}"
  local with_data="${6:-false}"
  local output_dir="${7:-./exports}"

  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log_error "Container '${container_name}' is not running"
    list_containers
    exit 1
  fi

  local container_id
  container_id=$(docker ps -qf "name=^${container_name}$")

  local base_image
  base_image=$(docker inspect --format='{{.Config.Image}}' "$container_name")

  log_info "Container: ${container_name} (${container_id})"
  log_info "Base image: ${base_image}"
  log_info "Target image: ${image_name}"
  log_info "Message: ${message}"
  log_info "Author: ${author}"

  read -p "Proceed with export? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Export cancelled"
    exit 0
  fi

  local commit_cmd="docker commit"

  if [ "$pause" = "false" ]; then
    commit_cmd="$commit_cmd --pause=false"
    log_warn "Container will NOT be paused during commit"
  else
    log_info "Container will be paused during commit"
  fi

  commit_cmd="$commit_cmd --message=\"${message}\" --author=\"${author}\" ${container_name} ${image_name}"

  log_step "Committing container to image..."
  eval "$commit_cmd"

  if [ $? -eq 0 ]; then
    log_info "✅ Successfully created image: ${image_name}"

    log_info "Image details:"
    docker images "$image_name" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

    if [ "$with_data" = "true" ]; then
      local data_export_path
      data_export_path=$(export_volume_data "$container_name" "$output_dir")

      if [ -n "$data_export_path" ]; then
        log_info "📦 Complete export package created:"
        echo "  • Image: ${image_name}"
        echo "  • Volume data: ${data_export_path}"
        log_info "To use this export:"
        echo "  1. Load image: docker load -i <image-file> (if saved)"
        echo "  2. Start container from image"
        echo "  3. Restore data: cd ${data_export_path} && ./restore-volume-data.sh <container-name>"
      fi
    fi

    log_info "Next steps:"
    echo "  • Test the image: docker run --rm ${image_name}"
    echo "  • Push to local registry: docker tag ${image_name} localhost:5000/${image_name} && docker push localhost:5000/${image_name}"
    echo "  • Push to GHCR: ./scripts/push-to-ghcr.sh ${image_name} <repo-name> <tag>"
    echo "  • Save to file: docker save ${image_name} -o ${image_name//[:\/]/_}.tar"
  else
    log_error "Failed to create image"
    exit 1
  fi
}

main() {
  local message=""
  local author="$(whoami)"
  local pause="true"
  local with_data="false"
  local output_dir="./exports"
  local container_name=""
  local image_name=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        usage
        exit 0
        ;;
      -m|--message)
        message="$2"
        shift 2
        ;;
      -a|--author)
        author="$2"
        shift 2
        ;;
      -p|--pause)
        pause="true"
        shift
        ;;
      --no-pause)
        pause="false"
        shift
        ;;
      -d|--with-data)
        with_data="true"
        shift
        ;;
      -o|--output-dir)
        output_dir="$2"
        shift 2
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [ -z "$container_name" ]; then
          container_name="$1"
        elif [ -z "$image_name" ]; then
          image_name="$1"
        else
          log_error "Too many arguments"
          usage
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [ -z "$container_name" ] || [ -z "$image_name" ]; then
    log_error "Missing required arguments"
    usage
    exit 1
  fi

  if [[ ! "$image_name" =~ : ]]; then
    image_name="${image_name}:latest"
  fi

  if [ -z "$message" ]; then
    message="Exported from container ${container_name} at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  fi

  export_container "$container_name" "$image_name" "$message" "$author" "$pause" "$with_data" "$output_dir"
}

main "$@"
