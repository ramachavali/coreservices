#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

<<<<<<< HEAD
=======
# Script to restore volume data to a Docker container
# This script is designed to work with exports created by export-container-image.sh

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

usage() {
  cat << EOF
Usage: $0 [OPTIONS] CONTAINER_NAME [EXPORT_DIR]

Restore volume data to a running Docker container.

Arguments:
  CONTAINER_NAME  Name of the running container to restore data to
  EXPORT_DIR      Directory containing volume exports (default: current directory)

Options:
  -h, --help      Show this help message
  -f, --force     Skip confirmation prompt

Examples:
  # Restore from current directory
<<<<<<< HEAD
  $0 vault

  # Restore from specific export directory
  $0 vault ./exports/vault_data_20260529_123456

  # Restore without confirmation
  $0 --force vault ./exports/vault_data_20260529_123456
=======
  $0 logto

  # Restore from specific export directory
  $0 logto ./exports/logto_data_20260529_123456

  # Restore without confirmation
  $0 --force logto ./exports/logto_data_20260529_123456
>>>>>>> b005e7b (updates)

EOF
}

<<<<<<< HEAD
=======
# Main restore function
>>>>>>> b005e7b (updates)
restore_volumes() {
  local container_name="$1"
  local export_dir="${2:-.}"
  local force="${3:-false}"
<<<<<<< HEAD

  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log_error "Container '${container_name}' is not running"
=======
  
  # Check if container is running
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log_error "Container '${container_name}' is not running"
    echo ""
>>>>>>> b005e7b (updates)
    log_info "Running containers:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    exit 1
  fi
<<<<<<< HEAD

=======
  
  # Check if export directory exists
>>>>>>> b005e7b (updates)
  if [ ! -d "$export_dir" ]; then
    log_error "Export directory not found: ${export_dir}"
    exit 1
  fi
<<<<<<< HEAD

  local metadata_files
  metadata_files=$(find "$export_dir" -maxdepth 1 -name "volume_*.json" 2>/dev/null || true)

=======
  
  # Find volume metadata files
  local metadata_files
  metadata_files=$(find "$export_dir" -maxdepth 1 -name "volume_*.json" 2>/dev/null || true)
  
>>>>>>> b005e7b (updates)
  if [ -z "$metadata_files" ]; then
    log_error "No volume metadata files found in ${export_dir}"
    log_info "Expected files: volume_*.json"
    exit 1
  fi
<<<<<<< HEAD

  log_info "Container: ${container_name}"
  log_info "Export directory: ${export_dir}"
  log_info "Volumes to restore:"

=======
  
  # Display what will be restored
  log_info "Container: ${container_name}"
  log_info "Export directory: ${export_dir}"
  echo ""
  log_info "Volumes to restore:"
  
>>>>>>> b005e7b (updates)
  for metadata_file in $metadata_files; do
    if [ -f "$metadata_file" ]; then
      local mount_point=$(grep -o '"mount_point": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
      local archive=$(grep -o '"archive": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
      local archive_path="${export_dir}/${archive}"
<<<<<<< HEAD

=======
      
>>>>>>> b005e7b (updates)
      if [ -f "$archive_path" ]; then
        echo "  • ${mount_point} <- ${archive}"
      else
        log_warn "Archive not found: ${archive}"
      fi
    fi
  done
<<<<<<< HEAD

  if [ "$force" != "true" ]; then
=======
  
  # Confirm restore
  if [ "$force" != "true" ]; then
    echo ""
>>>>>>> b005e7b (updates)
    read -p "Proceed with restore? This will overwrite existing data. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_warn "Restore cancelled"
      exit 0
    fi
  fi
<<<<<<< HEAD

  log_step "Starting volume restore..."

  local restored_count=0
  local failed_count=0

=======
  
  # Restore each volume
  echo ""
  log_step "Starting volume restore..."
  
  local restored_count=0
  local failed_count=0
  
>>>>>>> b005e7b (updates)
  for metadata_file in $metadata_files; do
    if [ -f "$metadata_file" ]; then
      local mount_point=$(grep -o '"mount_point": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
      local archive=$(grep -o '"archive": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
      local archive_path="${export_dir}/${archive}"
<<<<<<< HEAD

=======
      
>>>>>>> b005e7b (updates)
      if [ ! -f "$archive_path" ]; then
        log_warn "Skipping ${mount_point}: archive not found"
        failed_count=$((failed_count + 1))
        continue
      fi
<<<<<<< HEAD

      log_step "Restoring: ${mount_point}"
      log_info "From: ${archive}"

=======
      
      log_step "Restoring: ${mount_point}"
      log_info "From: ${archive}"
      
      # Copy archive into container
>>>>>>> b005e7b (updates)
      if ! docker cp "$archive_path" "${container_name}:/tmp/${archive}" 2>/dev/null; then
        log_error "Failed to copy archive to container"
        failed_count=$((failed_count + 1))
        continue
      fi
<<<<<<< HEAD

=======
      
      # Extract archive in container
>>>>>>> b005e7b (updates)
      if docker exec "${container_name}" sh -c "cd ${mount_point} && tar -xzf /tmp/${archive} && rm /tmp/${archive}" 2>/dev/null; then
        log_info "✅ Restored ${mount_point}"
        restored_count=$((restored_count + 1))
      else
        log_error "Failed to extract archive in container"
<<<<<<< HEAD
=======
        # Clean up the copied archive
>>>>>>> b005e7b (updates)
        docker exec "${container_name}" rm -f "/tmp/${archive}" 2>/dev/null || true
        failed_count=$((failed_count + 1))
      fi
    fi
  done
<<<<<<< HEAD

=======
  
  # Summary
  echo ""
>>>>>>> b005e7b (updates)
  if [ $failed_count -eq 0 ]; then
    log_info "✅ All volumes restored successfully (${restored_count} volumes)"
  else
    log_warn "Restore completed with errors: ${restored_count} succeeded, ${failed_count} failed"
    exit 1
  fi
}

<<<<<<< HEAD
=======
# Main script
>>>>>>> b005e7b (updates)
main() {
  local container_name=""
  local export_dir="."
  local force="false"
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
      -f|--force)
        force="true"
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [ -z "$container_name" ]; then
          container_name="$1"
        elif [ "$export_dir" = "." ]; then
          export_dir="$1"
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
  if [ -z "$container_name" ]; then
    log_error "Container name required"
    usage
    exit 1
  fi
<<<<<<< HEAD

=======
  
  # Restore volumes
>>>>>>> b005e7b (updates)
  restore_volumes "$container_name" "$export_dir" "$force"
}

main "$@"
<<<<<<< HEAD
=======

# Made with Bob
>>>>>>> b005e7b (updates)
