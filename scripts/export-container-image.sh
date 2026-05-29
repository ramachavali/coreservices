#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

<<<<<<< HEAD
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

=======
# Script to export a running Docker container as a custom image
# Useful for capturing container state with modifications

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
>>>>>>> b005e7b (updates)
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

<<<<<<< HEAD
=======
# Display usage
>>>>>>> b005e7b (updates)
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
<<<<<<< HEAD
  $0 vault my-custom-vault

  # Export with specific tag
  $0 vault my-custom-vault:v1.0.0

  # Export with commit message
  $0 -m "Added custom configuration" vault my-custom-vault:configured
=======
  $0 logto my-custom-logto

  # Export with specific tag
  $0 logto my-custom-logto:v1.0.0

  # Export with commit message
  $0 -m "Added custom configuration" logto my-custom-logto:configured
>>>>>>> b005e7b (updates)

  # Export without pausing (for containers that can't be paused)
  $0 --no-pause vault my-custom-vault:latest

  # Export with volume data included
<<<<<<< HEAD
  $0 --with-data vault my-custom-vault:v1.0.0

  # Export with data to specific directory
  $0 --with-data --output-dir ./backups vault my-custom-vault:v1.0.0

  # Export and push to GHCR in one go
  $0 vault my-custom-vault:v1.0.0 && ./scripts/push-to-ghcr.sh my-custom-vault:v1.0.0 my-custom-vault v1.0.0
=======
  $0 --with-data logto my-custom-logto:v1.0.0

  # Export with data to specific directory
  $0 --with-data --output-dir ./backups logto my-custom-logto:v1.0.0

  # Export and push to GHCR in one go
  $0 logto my-custom-logto:v1.0.0 && ./scripts/push-to-ghcr.sh my-custom-logto:v1.0.0 my-custom-logto v1.0.0
>>>>>>> b005e7b (updates)

Common Workflow:
  1. Make changes to a running container
  2. Export container as custom image: $0 container-name my-image:tag
  3. Push to GHCR: ./scripts/push-to-ghcr.sh my-image:tag repo-name tag
  4. Use in docker-compose or pull on other systems

EOF
}

<<<<<<< HEAD
=======
# List running containers
>>>>>>> b005e7b (updates)
list_containers() {
  log_info "Running containers:"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

<<<<<<< HEAD
=======
# Get container volumes
>>>>>>> b005e7b (updates)
get_container_volumes() {
  local container_name="$1"
  docker inspect "$container_name" --format='{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.Type}}{{"\n"}}{{end}}' 2>/dev/null || echo ""
}

<<<<<<< HEAD
=======
# Export volume data
>>>>>>> b005e7b (updates)
export_volume_data() {
  local container_name="$1"
  local output_dir="$2"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local export_name="${container_name}_data_${timestamp}"
  local export_path="${output_dir}/${export_name}"
<<<<<<< HEAD

  log_step "Exporting volume data for container: ${container_name}"

  mkdir -p "$export_path"

  local volumes
  volumes=$(get_container_volumes "$container_name")

=======
  
  log_step "Exporting volume data for container: ${container_name}"
  
  # Create output directory
  mkdir -p "$export_path"
  
  # Get volume mounts
  local volumes
  volumes=$(get_container_volumes "$container_name")
  
>>>>>>> b005e7b (updates)
  if [ -z "$volumes" ]; then
    log_warn "No volumes found for container ${container_name}"
    return 0
  fi
<<<<<<< HEAD

=======
  
>>>>>>> b005e7b (updates)
  log_info "Found volumes:"
  echo "$volumes" | while IFS=: read -r source dest type; do
    if [ -n "$source" ]; then
      echo "  • ${dest} (${type}): ${source}"
    fi
  done
<<<<<<< HEAD

=======
  
  # Export each volume
>>>>>>> b005e7b (updates)
  local volume_count=0
  echo "$volumes" | while IFS=: read -r source dest type; do
    if [ -n "$source" ] && [ -d "$source" ]; then
      volume_count=$((volume_count + 1))
      local volume_name=$(basename "$dest" | tr '/' '_')
      local tar_file="${export_path}/volume_${volume_name}.tar.gz"
<<<<<<< HEAD

      log_step "Backing up volume: ${dest}"
      log_info "Source: ${source}"
      log_info "Archive: ${tar_file}"

=======
      
      log_step "Backing up volume: ${dest}"
      log_info "Source: ${source}"
      log_info "Archive: ${tar_file}"
      
      # Create tarball of volume data
>>>>>>> b005e7b (updates)
      tar -czf "$tar_file" -C "$source" . 2>/dev/null || {
        log_warn "Failed to backup ${dest}, skipping..."
        continue
      }
<<<<<<< HEAD

=======
      
      # Create metadata file
>>>>>>> b005e7b (updates)
      cat > "${export_path}/volume_${volume_name}.json" << METADATA
{
  "container": "${container_name}",
  "mount_point": "${dest}",
  "source": "${source}",
  "type": "${type}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "archive": "volume_${volume_name}.tar.gz"
}
METADATA
<<<<<<< HEAD

      log_info "✅ Backed up ${dest}"
    fi
  done

=======
      
      log_info "✅ Backed up ${dest}"
    fi
  done
  
  # Copy restore script to export directory
>>>>>>> b005e7b (updates)
  local restore_script="${PROJECT_ROOT}/scripts/restore-volume-data.sh"
  if [ -f "$restore_script" ]; then
    cp "$restore_script" "${export_path}/restore-volume-data.sh"
    log_info "✅ Restore script copied to export directory"
  else
    log_warn "Restore script not found at ${restore_script}"
  fi
<<<<<<< HEAD

=======
  
  # Create README with instructions
>>>>>>> b005e7b (updates)
  cat > "${export_path}/README.md" << 'README'
# Volume Data Export

This directory contains exported volume data from a Docker container.

## Contents

- `volume_*.tar.gz` - Compressed volume data archives
- `volume_*.json` - Metadata for each volume (mount points, timestamps, etc.)
- `restore-volume-data.sh` - Script to restore volumes to a container

## Restore Instructions

1. **Start your target container:**
   ```bash
   docker run -d --name <container-name> <image-name>
   ```

2. **Run the restore script:**
   ```bash
   ./restore-volume-data.sh <container-name>
   ```

   Or from the scripts directory:
   ```bash
   ../../scripts/restore-volume-data.sh <container-name> .
   ```

3. **Verify the restoration:**
   ```bash
   docker exec <container-name> ls -la <mount-point>
   ```

## Options

- Use `--force` to skip confirmation prompt
- Specify export directory as second argument if not in current directory

## Example

```bash
<<<<<<< HEAD
# Restore to container named 'vault'
./restore-volume-data.sh vault

# Restore with force flag
./restore-volume-data.sh --force vault
```
README

  log_info "✅ Volume data exported to: ${export_path}"
  log_info "To restore: cd ${export_path} && ./restore-volume-data.sh <container_name>"

=======
# Restore to container named 'logto'
./restore-volume-data.sh logto

# Restore with force flag
./restore-volume-data.sh --force logto
```
README
  
  log_info "✅ Volume data exported to: ${export_path}"
  log_info "To restore: cd ${export_path} && ./restore-volume-data.sh <container_name>"
  
>>>>>>> b005e7b (updates)
  echo "$export_path"
}
}

<<<<<<< HEAD
=======
# Export container as image
>>>>>>> b005e7b (updates)
export_container() {
  local container_name="$1"
  local image_name="$2"
  local message="${3:-Exported from container ${container_name}}"
  local author="${4:-$(whoami)}"
  local pause="${5:-true}"
  local with_data="${6:-false}"
  local output_dir="${7:-./exports}"
<<<<<<< HEAD

  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log_error "Container '${container_name}' is not running"
    list_containers
    exit 1
  fi

  local container_id
  container_id=$(docker ps -qf "name=^${container_name}$")

  local base_image
  base_image=$(docker inspect --format='{{.Config.Image}}' "$container_name")

=======
  
  # Check if container exists and is running
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log_error "Container '${container_name}' is not running"
    echo ""
    list_containers
    exit 1
  fi
  
  # Get container info
  local container_id
  container_id=$(docker ps -qf "name=^${container_name}$")
  
  local base_image
  base_image=$(docker inspect --format='{{.Config.Image}}' "$container_name")
  
>>>>>>> b005e7b (updates)
  log_info "Container: ${container_name} (${container_id})"
  log_info "Base image: ${base_image}"
  log_info "Target image: ${image_name}"
  log_info "Message: ${message}"
  log_info "Author: ${author}"
<<<<<<< HEAD

=======
  
  # Confirm action
  echo ""
>>>>>>> b005e7b (updates)
  read -p "Proceed with export? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Export cancelled"
    exit 0
  fi
<<<<<<< HEAD

  local commit_cmd="docker commit"

=======
  
  # Build commit command
  local commit_cmd="docker commit"
  
>>>>>>> b005e7b (updates)
  if [ "$pause" = "false" ]; then
    commit_cmd="$commit_cmd --pause=false"
    log_warn "Container will NOT be paused during commit"
  else
    log_info "Container will be paused during commit"
  fi
<<<<<<< HEAD

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
=======
  
  commit_cmd="$commit_cmd --message=\"${message}\" --author=\"${author}\" ${container_name} ${image_name}"
  
  # Execute commit
  log_step "Committing container to image..."
  eval "$commit_cmd"
  
  if [ $? -eq 0 ]; then
    log_info "✅ Successfully created image: ${image_name}"
    echo ""
    
    # Show image details
    log_info "Image details:"
    docker images "$image_name" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    
    # Export volume data if requested
    if [ "$with_data" = "true" ]; then
      echo ""
      local data_export_path
      data_export_path=$(export_volume_data "$container_name" "$output_dir")
      
      if [ -n "$data_export_path" ]; then
        echo ""
        log_info "📦 Complete export package created:"
        echo "  • Image: ${image_name}"
        echo "  • Volume data: ${data_export_path}"
        echo ""
>>>>>>> b005e7b (updates)
        log_info "To use this export:"
        echo "  1. Load image: docker load -i <image-file> (if saved)"
        echo "  2. Start container from image"
        echo "  3. Restore data: cd ${data_export_path} && ./restore-volume-data.sh <container-name>"
      fi
    fi
<<<<<<< HEAD

=======
    
    echo ""
>>>>>>> b005e7b (updates)
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

<<<<<<< HEAD
=======
# Main script
>>>>>>> b005e7b (updates)
main() {
  local message=""
  local author="$(whoami)"
  local pause="true"
  local with_data="false"
  local output_dir="./exports"
  local container_name=""
  local image_name=""
<<<<<<< HEAD

=======
  
  # Parse arguments
>>>>>>> b005e7b (updates)
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
<<<<<<< HEAD

=======
  
  # Validate required arguments
>>>>>>> b005e7b (updates)
  if [ -z "$container_name" ] || [ -z "$image_name" ]; then
    log_error "Missing required arguments"
    usage
    exit 1
  fi
<<<<<<< HEAD

  if [[ ! "$image_name" =~ : ]]; then
    image_name="${image_name}:latest"
  fi

  if [ -z "$message" ]; then
    message="Exported from container ${container_name} at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  fi

=======
  
  # Add :latest tag if not specified
  if [[ ! "$image_name" =~ : ]]; then
    image_name="${image_name}:latest"
  fi
  
  # Set default message if not provided
  if [ -z "$message" ]; then
    message="Exported from container ${container_name} at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  fi
  
  # Export container
>>>>>>> b005e7b (updates)
  export_container "$container_name" "$image_name" "$message" "$author" "$pause" "$with_data" "$output_dir"
}

main "$@"
<<<<<<< HEAD
=======

# Made with Bob
>>>>>>> b005e7b (updates)
