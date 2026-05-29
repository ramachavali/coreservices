-- Authentication PostgreSQL Initialization Script
-- Creates databases and users for Keycloak and Vault OIDC integration
-- This script runs automatically on first container startup

-- Enable pgvector extension on template database
CREATE EXTENSION IF NOT EXISTS vector;

-- Create Keycloak database and user
CREATE DATABASE keycloak;
CREATE USER keycloak_user WITH ENCRYPTED PASSWORD 'KEYCLOAK_DB_PASSWORD_PLACEHOLDER';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak_user;

-- Connect to keycloak database and set permissions
\c keycloak
GRANT ALL ON SCHEMA public TO keycloak_user;
ALTER DATABASE keycloak OWNER TO keycloak_user;

-- Enable pgvector extension in keycloak database
CREATE EXTENSION IF NOT EXISTS vector;

-- Create Vault OIDC database and user
\c postgres
CREATE DATABASE vault_oidc;
CREATE USER vault_user WITH ENCRYPTED PASSWORD 'VAULT_DB_PASSWORD_PLACEHOLDER';
GRANT ALL PRIVILEGES ON DATABASE vault_oidc TO vault_user;

-- Connect to vault_oidc database and set permissions
\c vault_oidc
GRANT ALL ON SCHEMA public TO vault_user;
ALTER DATABASE vault_oidc OWNER TO vault_user;

-- Enable pgvector extension in vault_oidc database
CREATE EXTENSION IF NOT EXISTS vector;

-- Return to postgres database
\c postgres

-- Create read-only monitoring user
CREATE USER auth_monitor WITH ENCRYPTED PASSWORD 'AUTH_MONITOR_PASSWORD_PLACEHOLDER';
GRANT CONNECT ON DATABASE keycloak TO auth_monitor;
GRANT CONNECT ON DATABASE vault_oidc TO auth_monitor;

\c keycloak
GRANT USAGE ON SCHEMA public TO auth_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auth_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO auth_monitor;

\c vault_oidc
GRANT USAGE ON SCHEMA public TO auth_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auth_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO auth_monitor;

\c postgres

DO $$
BEGIN
    RAISE NOTICE 'Authentication database initialization complete';
    RAISE NOTICE 'Created databases: keycloak, vault_oidc';
    RAISE NOTICE 'Created users: keycloak_user, vault_user, auth_monitor';
END $$;
