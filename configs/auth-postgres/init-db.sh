#!/usr/bin/env bash
set -euo pipefail

: "${KEYCLOAK_DB_PASSWORD:?KEYCLOAK_DB_PASSWORD is required}"
: "${AUTH_MONITOR_PASSWORD:?AUTH_MONITOR_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
CREATE DATABASE keycloak;
CREATE USER keycloak_user WITH ENCRYPTED PASSWORD '${KEYCLOAK_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak_user;
ALTER DATABASE keycloak OWNER TO keycloak_user;
SQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d keycloak <<SQL
GRANT ALL ON SCHEMA public TO keycloak_user;
SQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
CREATE USER auth_monitor WITH ENCRYPTED PASSWORD '${AUTH_MONITOR_PASSWORD}';
GRANT CONNECT ON DATABASE keycloak TO auth_monitor;
SQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d keycloak <<SQL
GRANT USAGE ON SCHEMA public TO auth_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auth_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO auth_monitor;
SQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
DO \$\$
BEGIN
    RAISE NOTICE 'Auth DB init complete: keycloak db, keycloak_user, auth_monitor';
END \$\$;
SQL
