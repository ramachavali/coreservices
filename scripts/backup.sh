#!/usr/bin/env bash

# =================================================================
# Core Services Backup Script
# Comprehensive backup for all Core Services data
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

# Load environment variables
if [ -f ./.rendered.env ]; then
    # shellcheck disable=SC1091
    source ./.rendered.env
fi

echo -e "💾 Core Services Backup Utility"

# Configuration
BACKUP_DIR="${BACKUP_LOCATION:-$HOME/Documents/coreservices-backups}"
DATE=$(date +%Y%m%d_%H%M%S)
ENCRYPT="${BACKUP_ENCRYPT:-false}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Parse command line arguments
BACKUP_TYPE="full"
SERVICES=""
COMPRESS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --type|-t)
            BACKUP_TYPE="$2"
            shift 2
            ;;
        --service|-s)
            SERVICES="$2"
            shift 2
            ;;
        --no-compress)
            COMPRESS=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo -e "\nOptions:"
            echo "  --type, -t       Backup type: full, data, config (default: full)"
            echo "  --service, -s    Specific service: auth-postgres, vault, grafana, etc."
            echo "  --no-compress    Skip compression (faster, larger files)"
            echo "  --help, -h       Show this help message"
            echo -e "\nExamples:"
            echo "  $0                       # Full backup"
            echo "  $0 --type data           # Data only backup"
            echo "  $0 --service vault        # Vault only"
            exit 0
            ;;
        *)
            echo -e "Unknown option: $1"
            exit 1
            ;;
    esac
done

encrypt_file() {
    local file="$1"
    if [ "$ENCRYPT" = "true" ] && [ -n "$ENCRYPTION_KEY" ]; then
        echo -e "🔒 Encrypting $(basename "$file")..."
        openssl enc -aes-256-cbc -in "$file" -out "${file}.enc" -pass pass:"$ENCRYPTION_KEY"
        rm "$file"
        echo "${file}.enc"
    else
        echo "$file"
    fi
}

check_services() {
    echo -e "🔍 Checking service status..."
    if compose_service_exists "auth-postgres" && ! "${COMPOSE_CMD[@]}" ps --services --filter "status=running" | grep -q "^auth-postgres$"; then
        echo -e "⚠️ auth-postgres is not running. Some backups may be incomplete."
    else
        echo -e "✅ auth-postgres is running"
    fi
}

setup_backup_dir() {
    echo -e "📁 Setting up backup directory..."
    mkdir -p "$BACKUP_DIR"
    echo -e "✅ Backup directory: $BACKUP_DIR"
}

backup_postgres() {
    echo -e "🐘 Backing up auth-postgres..."
    local pg_user="${AUTH_POSTGRES_USER:-pgcore}"
    local pg_db="${AUTH_POSTGRES_DB:-postgres}"

    echo "  📊 Backing up database: $pg_db..."
    if [ "$COMPRESS" = true ]; then
        docker exec auth-postgres pg_dump -U "$pg_user" "$pg_db" | gzip > "$BACKUP_DIR/auth_postgres_${DATE}.sql.gz"
        encrypt_file "$BACKUP_DIR/auth_postgres_${DATE}.sql.gz"
    else
        docker exec auth-postgres pg_dump -U "$pg_user" "$pg_db" > "$BACKUP_DIR/auth_postgres_${DATE}.sql"
        encrypt_file "$BACKUP_DIR/auth_postgres_${DATE}.sql"
    fi

    echo -e "✅ auth-postgres backup completed"
}

backup_volumes() {
    echo -e "💾 Backing up Docker volumes..."

    local volumes=()
    while IFS= read -r volume; do
        [ -n "$volume" ] && volumes+=("$volume")
    done < <(compose_volume_list)

    if [ ${#volumes[@]} -eq 0 ]; then
        echo -e "    ⚠️ No named volumes found in compose configuration"
    fi

    for volume in "${volumes[@]}"; do
        echo "  📁 Backing up volume: $volume..."
        if docker volume inspect "$volume" > /dev/null 2>&1; then
            if [ "$COMPRESS" = true ]; then
                docker run --rm \
                    -v "$volume:/data" \
                    -v "$BACKUP_DIR":/backup \
                    alpine tar czf "/backup/${volume}_${DATE}.tar.gz" -C /data .
                encrypt_file "$BACKUP_DIR/${volume}_${DATE}.tar.gz"
            else
                docker run --rm \
                    -v "$volume:/data" \
                    -v "$BACKUP_DIR":/backup \
                    alpine tar cf "/backup/${volume}_${DATE}.tar" -C /data .
                encrypt_file "$BACKUP_DIR/${volume}_${DATE}.tar"
            fi
        else
            echo -e "    ⚠️ Volume $volume not found, skipping"
        fi
    done

    echo -e "✅ Volume backup completed"
}

backup_configs() {
    echo -e "⚙️ Backing up configuration files..."

    if [ -d configs ]; then
        echo "  📋 Backing up configs directory..."
        if [ "$COMPRESS" = true ]; then
            tar czf "$BACKUP_DIR/configs_${DATE}.tar.gz" configs/
            encrypt_file "$BACKUP_DIR/configs_${DATE}.tar.gz"
        else
            tar cf "$BACKUP_DIR/configs_${DATE}.tar" configs/
            encrypt_file "$BACKUP_DIR/configs_${DATE}.tar"
        fi
    fi

    echo "  📋 Backing up docker-compose.yml..."
    cp docker-compose.yml "$BACKUP_DIR/docker-compose_${DATE}.yml"
    encrypt_file "$BACKUP_DIR/docker-compose_${DATE}.yml"

    echo -e "✅ Configuration backup completed"
}

backup_service() {
    local service="$1"
    echo -e "🎯 Backing up service: $service"

    case "$service" in
        auth-postgres|postgres)
            backup_postgres
            ;;
        vault|grafana|loki|redis|keycloak|traefik|registry|alloy)
            echo "  💾 Backing up ${service} data..."
            local volume_name="${service}_data"
            if [ "$service" = "traefik" ]; then
                # traefik has two volumes
                for vol in traefik_certs traefik_logs; do
                    if docker volume inspect "$vol" > /dev/null 2>&1; then
                        if [ "$COMPRESS" = true ]; then
                            docker run --rm -v "$vol:/data" -v "$BACKUP_DIR":/backup \
                                alpine tar czf "/backup/${vol}_${DATE}.tar.gz" -C /data .
                            encrypt_file "$BACKUP_DIR/${vol}_${DATE}.tar.gz"
                        else
                            docker run --rm -v "$vol:/data" -v "$BACKUP_DIR":/backup \
                                alpine tar cf "/backup/${vol}_${DATE}.tar" -C /data .
                            encrypt_file "$BACKUP_DIR/${vol}_${DATE}.tar"
                        fi
                    fi
                done
                echo -e "✅ traefik backup completed"
                return
            fi
            if docker volume inspect "$volume_name" > /dev/null 2>&1; then
                if [ "$COMPRESS" = true ]; then
                    docker run --rm \
                        -v "$volume_name:/data" \
                        -v "$BACKUP_DIR":/backup \
                        alpine tar czf "/backup/${volume_name}_${DATE}.tar.gz" -C /data .
                    encrypt_file "$BACKUP_DIR/${volume_name}_${DATE}.tar.gz"
                else
                    docker run --rm \
                        -v "$volume_name:/data" \
                        -v "$BACKUP_DIR":/backup \
                        alpine tar cf "/backup/${volume_name}_${DATE}.tar" -C /data .
                    encrypt_file "$BACKUP_DIR/${volume_name}_${DATE}.tar"
                fi
                echo -e "✅ $service backup completed"
            else
                echo -e "⚠️ Volume for $service not found"
            fi
            ;;
        *)
            echo -e "❌ Unknown service: $service"
            exit 1
            ;;
    esac
}

create_manifest() {
    echo -e "📋 Creating backup manifest..."

    local manifest_file="$BACKUP_DIR/backup_manifest_${DATE}.json"
    local template_file="$PROJECT_ROOT/configs/backup/manifest.json.template"

    if [ ! -f "$template_file" ]; then
        echo -e "❌ Manifest template not found: $template_file"
        return 1
    fi

    local files_json
    files_json=$(find "$BACKUP_DIR" -name "*_${DATE}.*" -type f | sed 's/.*/"&"/' | paste -sd, - | sed 's/^/[/;s/$$/]/')

    sed \
        -e "s|{{BACKUP_DATE}}|$DATE|g" \
        -e "s|{{BACKUP_TYPE}}|$BACKUP_TYPE|g" \
        -e "s|{{SERVICES}}|$SERVICES|g" \
        -e "s|{{COMPRESS}}|$COMPRESS|g" \
        -e "s|{{ENCRYPT}}|$ENCRYPT|g" \
        -e "s|{{FILES_JSON}}|$files_json|g" \
        "$template_file" > "$manifest_file"

    echo -e "✅ Backup manifest created"
}

cleanup_old_backups() {
    echo -e "🧹 Cleaning up old backups..."

    if [ "$RETENTION_DAYS" -gt 0 ]; then
        echo "  🗑️ Removing backups older than $RETENTION_DAYS days..."
        find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -name "*.gz" -delete 2>/dev/null || true
        find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -name "*.tar" -delete 2>/dev/null || true
        find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -name "*.sql" -delete 2>/dev/null || true
        find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -name "*.enc" -delete 2>/dev/null || true
        find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -name "backup_manifest_*.json" -delete 2>/dev/null || true
        echo -e "✅ Cleanup completed"
    else
        echo "  ℹ️ Cleanup disabled (retention set to 0)"
    fi
}

show_summary() {
    echo -e "\n🎉 Backup Completed Successfully!"
    echo "📅 Date: $DATE"
    echo "🗂️ Type: $BACKUP_TYPE"
    echo "📍 Location: $BACKUP_DIR"
    echo "🔒 Encrypted: $ENCRYPT"
    echo "📦 Compressed: $COMPRESS"

    if [ -n "$SERVICES" ]; then
        echo "🎯 Services: $SERVICES"
    fi

    echo -e "\n📊 Backup Files:"
    find "$BACKUP_DIR" -name "*_${DATE}.*" -type f | while read -r file; do
        size=$(du -h "$file" | cut -f1)
        echo "  📄 $(basename "$file") ($size)"
    done

    echo -e "\n💡 To restore this backup:"
    echo "  ./scripts/restore.sh --date $DATE"
}

main() {
    check_services
    setup_backup_dir

    echo -e "🔄 Starting $BACKUP_TYPE backup..."

    case "$BACKUP_TYPE" in
        full)
            if [ -n "$SERVICES" ]; then
                backup_service "$SERVICES"
            else
                backup_postgres
                backup_volumes
                backup_configs
            fi
            ;;
        data)
            if [ -n "$SERVICES" ]; then
                backup_service "$SERVICES"
            else
                backup_postgres
                backup_volumes
            fi
            ;;
        config)
            backup_configs
            ;;
        *)
            echo -e "❌ Unknown backup type: $BACKUP_TYPE"
            echo "Available types: full, data, config"
            exit 1
            ;;
    esac

    create_manifest
    cleanup_old_backups
    show_summary
}

main "$@"
