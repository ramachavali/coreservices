#!/usr/bin/env bash

# =================================================================
# Core Services Restore Script
# Restore from backups with verification
# =================================================================

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

COMPOSE_CMD=(docker-compose)

compose_volume_list() {
    local compose_volumes=()
    while IFS= read -r vol; do
        [ -n "$vol" ] && compose_volumes+=("$vol")
    done < <("${COMPOSE_CMD[@]}" config --volumes)
    printf '%s\n' "${compose_volumes[@]}"
}

compose_service_exists() {
    local target="$1"
    local compose_services=()
    while IFS= read -r svc; do
        compose_services+=("$svc")
    done < <("${COMPOSE_CMD[@]}" config --services)
    for svc in "${compose_services[@]}"; do
        [ "$svc" = "$target" ] && return 0
    done
    return 1
}

if [ -f ./.rendered.env ]; then
    # shellcheck disable=SC1091
    source ./.rendered.env
fi

# Configuration
BACKUP_DIR="${BACKUP_LOCATION:-$HOME/Documents/coreservices-backups}"
ENCRYPT="${BACKUP_ENCRYPT:-false}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

echo -e "🔄 Core Services Restore Utility"

# Parse command line arguments
RESTORE_DATE=""
RESTORE_TYPE="full"
SERVICES=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --date|-d)
            RESTORE_DATE="$2"
            shift 2
            ;;
        --type|-t)
            RESTORE_TYPE="$2"
            shift 2
            ;;
        --service|-s)
            SERVICES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --list|-l)
            echo -e "📋 Available backups:"
            if [ -d "$BACKUP_DIR" ]; then
                find "$BACKUP_DIR" -name "backup_manifest_*.json" | sort -r | while read -r manifest; do
                    date_part=$(basename "$manifest" | sed 's/backup_manifest_//' | sed 's/.json//')
                    echo -e "\n📅 $date_part"
                    if command -v jq > /dev/null 2>&1; then
                        jq -r '. | "   Type: \(.backup_type)\n   Date: \(.backup_date)\n   Files: \(.files | length)"' "$manifest" 2>/dev/null || echo "   (Manifest details unavailable)"
                    fi
                done
            else
                echo "No backup directory found at: $BACKUP_DIR"
            fi
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo -e "\nOptions:"
            echo "  --date, -d      Restore from specific backup date (YYYYMMDD_HHMMSS)"
            echo "  --type, -t      Restore type: full, data, config (default: full)"
            echo "  --service, -s   Specific service: auth-postgres, vault, grafana, etc."
            echo "  --dry-run       Show what would be restored without actually doing it"
            echo "  --list, -l      List available backups"
            echo "  --help, -h      Show this help message"
            echo -e "\nExamples:"
            echo "  $0 --list                    # List available backups"
            echo "  $0 --date 20240101_120000    # Restore full backup from specific date"
            echo "  $0 --service vault            # Restore only Vault from latest backup"
            exit 0
            ;;
        *)
            echo -e "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find latest backup if no date specified
if [ -z "$RESTORE_DATE" ]; then
    echo -e "🔍 Finding latest backup..."
    latest_manifest=$(find "$BACKUP_DIR" -name "backup_manifest_*.json" 2>/dev/null | sort -r | head -n1 || true)
    if [ -z "$latest_manifest" ]; then
        echo -e "❌ No backups found in $BACKUP_DIR"
        exit 1
    fi
    RESTORE_DATE=$(basename "$latest_manifest" | sed 's/backup_manifest_//' | sed 's/.json//')
    echo -e "📅 Using latest backup: $RESTORE_DATE"
fi

# Verify backup exists
MANIFEST_FILE="$BACKUP_DIR/backup_manifest_${RESTORE_DATE}.json"
if [ ! -f "$MANIFEST_FILE" ]; then
    echo -e "❌ Backup manifest not found: $MANIFEST_FILE"
    echo "Available backups:"
    find "$BACKUP_DIR" -name "backup_manifest_*.json" | sort -r | head -5
    exit 1
fi

echo -e "📋 Backup information:"
if command -v jq > /dev/null 2>&1; then
    jq -r '. | "Date: \(.backup_date)\nType: \(.backup_type)\nServices: \(.services)\nFiles: \(.files | length)"' "$MANIFEST_FILE"
else
    echo "Manifest: $MANIFEST_FILE"
fi

# Resolve a backup file, decrypting if needed.
# Prints the path to use; returns 1 and prints nothing if not found.
resolve_backup_file() {
    local file="$1"
    if [ -f "${file}.enc" ] && [ "$ENCRYPT" = "true" ] && [ -n "$ENCRYPTION_KEY" ]; then
        echo -e "🔓 Decrypting $(basename "$file")..." >&2
        openssl enc -aes-256-cbc -d -in "${file}.enc" -out "$file" -pass pass:"$ENCRYPTION_KEY"
        echo "$file"
    elif [ -f "$file" ]; then
        echo "$file"
    else
        return 1
    fi
}

# Delete a file only if it was produced by decryption (i.e., ENCRYPT=true).
cleanup_if_decrypted() {
    local file="$1"
    if [ "$ENCRYPT" = "true" ] && [ -n "$ENCRYPTION_KEY" ]; then
        rm -f "$file"
    fi
}

wait_for_postgres() {
    local pg_user="${AUTH_POSTGRES_USER:-pgcore}"
    echo -e "  ⏳ Waiting for auth-postgres to be ready..."
    for i in $(seq 1 30); do
        if docker exec auth-postgres pg_isready -U "$pg_user" > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo -e "❌ auth-postgres did not become ready in time"
    exit 1
}

restore_postgres() {
    echo -e "🐘 Restoring auth-postgres..."

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Would restore auth-postgres database"
        return
    fi

    if compose_service_exists "auth-postgres"; then
        "${COMPOSE_CMD[@]}" up -d auth-postgres
        wait_for_postgres
    else
        echo -e "❌ Service 'auth-postgres' not found in compose configuration"
        exit 1
    fi

    local pg_user="${AUTH_POSTGRES_USER:-pgcore}"
    local pg_db="${AUTH_POSTGRES_DB:-postgres}"

    local db_backup
    if db_backup=$(resolve_backup_file "$BACKUP_DIR/auth_postgres_${RESTORE_DATE}.sql.gz"); then
        echo "  📊 Restoring database: $pg_db..."
        zcat "$db_backup" | docker exec -i auth-postgres psql -U "$pg_user" -d "$pg_db"
        cleanup_if_decrypted "$db_backup"
    else
        echo "  ⚠️ No backup found for auth-postgres database"
    fi

    echo -e "✅ auth-postgres restore completed"
}

restore_volumes() {
    echo -e "💾 Restoring Docker volumes..."

    local volumes=()
    while IFS= read -r volume; do
        [ -n "$volume" ] && volumes+=("$volume")
    done < <(compose_volume_list)

    if [ ${#volumes[@]} -eq 0 ]; then
        echo -e "    ⚠️ No named volumes found in compose configuration"
    fi

    for volume in "${volumes[@]}"; do
        local volume_backup
        if volume_backup=$(resolve_backup_file "$BACKUP_DIR/${volume}_${RESTORE_DATE}.tar.gz") || \
           volume_backup=$(resolve_backup_file "$BACKUP_DIR/${volume}_${RESTORE_DATE}.tar"); then

            echo -e "  📁 Restoring ${volume}..."

            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY RUN] Would restore volume: ${volume}"
                cleanup_if_decrypted "$volume_backup"
                continue
            fi

            local tar_extract_flags="xf"
            case "$volume_backup" in
                *.tar.gz|*.tgz) tar_extract_flags="xzf" ;;
            esac

            docker volume rm "${volume}" 2>/dev/null || true
            docker volume create "${volume}"
            docker run --rm \
                -v "${volume}:/data" \
                -v "$BACKUP_DIR":/backup \
                alpine sh -c "cd /data && tar ${tar_extract_flags} /backup/$(basename "$volume_backup")"

            cleanup_if_decrypted "$volume_backup"
        else
            echo -e "    ⚠️ No backup found for volume: ${volume}, skipping"
        fi
    done

    echo -e "✅ Volume restore completed"
}

restore_configs() {
    echo -e "⚙️  Restoring configuration files..."

    local config_backup
    if config_backup=$(resolve_backup_file "$BACKUP_DIR/configs_${RESTORE_DATE}.tar.gz"); then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY RUN] Would restore configuration files"
        else
            if [ -d configs ]; then
                mv configs "configs.backup.$(date +%Y%m%d_%H%M%S)"
            fi
            tar xzf "$config_backup"
        fi
        cleanup_if_decrypted "$config_backup"
    else
        echo "  ⚠️ No config backup found, skipping"
    fi

    echo -e "✅ Configuration restore completed"
}

restore_service() {
    local service="$1"
    echo -e "🎯 Restoring service: $service"

    case "$service" in
        auth-postgres|postgres)
            restore_postgres
            ;;
        vault|grafana|loki|redis|keycloak|registry|alloy)
            local volume_name="${service}_data"

            local volume_backup
            if volume_backup=$(resolve_backup_file "$BACKUP_DIR/${volume_name}_${RESTORE_DATE}.tar.gz"); then
                if [ "$DRY_RUN" = true ]; then
                    echo "  [DRY RUN] Would restore ${service} data"
                else
                    docker volume rm "${volume_name}" 2>/dev/null || true
                    docker volume create "${volume_name}"
                    docker run --rm \
                        -v "${volume_name}:/data" \
                        -v "$BACKUP_DIR":/backup \
                        alpine sh -c "cd /data && tar xzf /backup/$(basename "$volume_backup")"
                fi
                cleanup_if_decrypted "$volume_backup"
            else
                echo -e "⚠️  No backup found for service: $service"
            fi
            ;;
        traefik)
            for vol in traefik_certs traefik_logs; do
                local vol_backup
                if vol_backup=$(resolve_backup_file "$BACKUP_DIR/${vol}_${RESTORE_DATE}.tar.gz"); then
                    if [ "$DRY_RUN" = true ]; then
                        echo "  [DRY RUN] Would restore ${vol}"
                    else
                        docker volume rm "${vol}" 2>/dev/null || true
                        docker volume create "${vol}"
                        docker run --rm \
                            -v "${vol}:/data" \
                            -v "$BACKUP_DIR":/backup \
                            alpine sh -c "cd /data && tar xzf /backup/$(basename "$vol_backup")"
                    fi
                    cleanup_if_decrypted "$vol_backup"
                else
                    echo -e "    ⚠️ No backup found for ${vol}, skipping"
                fi
            done
            echo -e "✅ traefik restore completed"
            ;;
        *)
            echo -e "❌ Unknown service: $service"
            exit 1
            ;;
    esac
}

# Warning for non-dry-run
if [ "$DRY_RUN" = false ]; then
    echo -e "⚠️  WARNING: This will overwrite existing data!"
    echo "Current data will be backed up before restoration."
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    echo -e "🛑 Stopping Core Services..."
    "${COMPOSE_CMD[@]}" down
fi

echo -e "🔄 Starting $RESTORE_TYPE restore..."

case "$RESTORE_TYPE" in
    full)
        if [ -n "$SERVICES" ]; then
            restore_service "$SERVICES"
        else
            restore_postgres
            restore_volumes
            restore_configs
        fi
        ;;
    data)
        if [ -n "$SERVICES" ]; then
            restore_service "$SERVICES"
        else
            restore_postgres
            restore_volumes
        fi
        ;;
    config)
        restore_configs
        ;;
    *)
        echo -e "❌ Unknown restore type: $RESTORE_TYPE"
        exit 1
        ;;
esac

if [ "$DRY_RUN" = false ]; then
    echo -e "\n🎉 Restore completed successfully!"
    echo "📅 Restored from: $RESTORE_DATE"
    echo "🔄 Type: $RESTORE_TYPE"
    echo -e "\nTo start Core Services with restored data:"
    echo "  ./scripts/start.sh"
else
    echo -e "\n🔍 Dry run completed"
    echo "No changes were made to the system."
fi
