# Keycloak Deployment Quick-Start Guide

This guide provides step-by-step instructions for deploying Keycloak authentication to your homelab infrastructure.

## Prerequisites

- Docker and Docker Compose installed
- `coreservices-homelab` stack running (Traefik, Vault, Grafana)
- `/etc/hosts` configured with `auth.local` pointing to your server

## Deployment Steps

### Step 1: Prepare Environment Variables

1. Navigate to coreservices-homelab directory:
```bash
cd /path/to/coreservices-homelab
```

2. Copy the environment template:
```bash
cp scripts/.unrendered.env .env
```

3. The `.env` file includes auto-generated passwords using `openssl rand -hex`. The Keycloak section includes:
```bash
# Authentication PostgreSQL Database
AUTH_POSTGRES_PASSWORD="$(openssl rand -hex 24)"

# Keycloak Database Credentials
KEYCLOAK_DB_PASSWORD="$(openssl rand -hex 24)"
VAULT_DB_PASSWORD="$(openssl rand -hex 24)"
AUTH_MONITOR_PASSWORD="$(openssl rand -hex 24)"

# Keycloak Admin Credentials
KEYCLOAK_ADMIN_USER="admin"
KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -hex 24)"

# Traefik ForwardAuth Secret
TRAEFIK_FORWARD_AUTH_SECRET="$(openssl rand -hex 32)"

# Keycloak Client Secrets (leave empty, will be generated later)
KEYCLOAK_OPENWEBUI_CLIENT_SECRET=""
KEYCLOAK_N8N_CLIENT_SECRET=""
# ... etc
```

4. **Note**: The passwords will be generated when you source the `.env` file or when Docker Compose reads it. The client secrets will be filled in after running the realm initialization script.

### Step 2: Update PostgreSQL Init Script

The init script has placeholders that need to be replaced with actual passwords:

```bash
# Edit the init script
nano configs/auth-postgres/init-db.sql

# Replace these placeholders with the passwords from your .env:
# - KEYCLOAK_DB_PASSWORD_PLACEHOLDER → value of KEYCLOAK_DB_PASSWORD
# - VAULT_DB_PASSWORD_PLACEHOLDER → value of VAULT_DB_PASSWORD
# - AUTH_MONITOR_PASSWORD_PLACEHOLDER → value of AUTH_MONITOR_PASSWORD
```

**Alternative**: Use sed to replace automatically:
```bash
sed -i "s/KEYCLOAK_DB_PASSWORD_PLACEHOLDER/$(grep KEYCLOAK_DB_PASSWORD .env | cut -d'=' -f2)/g" configs/auth-postgres/init-db.sql
sed -i "s/VAULT_DB_PASSWORD_PLACEHOLDER/$(grep VAULT_DB_PASSWORD .env | cut -d'=' -f2)/g" configs/auth-postgres/init-db.sql
sed -i "s/AUTH_MONITOR_PASSWORD_PLACEHOLDER/$(grep AUTH_MONITOR_PASSWORD .env | cut -d'=' -f2)/g" configs/auth-postgres/init-db.sql
```

### Step 3: Deploy Keycloak Infrastructure

1. Start the authentication database:
```bash
docker-compose up -d auth-postgres
```

2. Wait for database to be healthy (check logs):
```bash
docker-compose logs -f auth-postgres
# Wait for "database system is ready to accept connections"
# Press Ctrl+C to exit logs
```

3. Start Keycloak:
```bash
docker-compose up -d keycloak
```

4. Wait for Keycloak to be ready (~60-90 seconds):
```bash
docker-compose logs -f keycloak
# Wait for "Keycloak ... started"
# Press Ctrl+C to exit logs
```

5. Verify Keycloak is accessible:
```bash
curl -k https://auth.local/health/ready
# Should return: {"status":"UP"}
```

### Step 4: Initialize Keycloak Realm

1. Run the realm initialization script:
```bash
export KEYCLOAK_ADMIN_PASSWORD="<your-admin-password>"
./configs/keycloak/init-realm.sh
```

2. The script will:
   - Create the `homelab` realm
   - Create groups: `homelab-admins`, `homelab-users`, `homelab-monitoring`
   - Create OIDC clients for all services
   - Display client secrets

3. **IMPORTANT**: Copy the client secrets from the script output to your `.env` file:
```bash
# Example output:
# 📋 Client Secret: abc123...
# Add to .env as: KEYCLOAK_OPENWEBUI_CLIENT_SECRET=abc123...

# Add all client secrets to .env:
KEYCLOAK_OPENWEBUI_CLIENT_SECRET=<from-script>
KEYCLOAK_N8N_CLIENT_SECRET=<from-script>
KEYCLOAK_LITELLM_CLIENT_SECRET=<from-script>
KEYCLOAK_GRAFANA_CLIENT_SECRET=<from-script>
KEYCLOAK_VAULT_CLIENT_SECRET=<from-script>
KEYCLOAK_TRAEFIK_CLIENT_SECRET=<from-script>
```

### Step 5: Create Users in Keycloak

1. Access Keycloak admin console:
```
URL: https://auth.local
Username: admin
Password: <KEYCLOAK_ADMIN_PASSWORD from .env>
```

2. Navigate to the `homelab` realm (dropdown in top-left)

3. Create users:
   - Click **Users** in left menu
   - Click **Add user**
   - Fill in:
     - Username: `your-username`
     - Email: `your-email@example.com`
     - First Name: `Your`
     - Last Name: `Name`
     - Email Verified: `ON`
   - Click **Create**

4. Set user password:
   - Click **Credentials** tab
   - Click **Set password**
   - Enter password (twice)
   - Set **Temporary**: `OFF`
   - Click **Save**

5. Assign user to groups:
   - Click **Groups** tab
   - Click **Join Group**
   - Select `homelab-admins` (for admin access) or `homelab-users`
   - Click **Join**

### Step 6: Deploy Traefik ForwardAuth

1. Start the ForwardAuth service:
```bash
docker-compose up -d traefik-forward-auth
```

2. Verify it's running:
```bash
docker-compose ps traefik-forward-auth
docker-compose logs traefik-forward-auth
```

### Step 7: Configure Vault OIDC (Optional)

1. Ensure Vault is unsealed and you have a valid token

2. Set the Vault client secret:
```bash
export VAULT_OIDC_CLIENT_SECRET="<KEYCLOAK_VAULT_CLIENT_SECRET from .env>"
```

3. Run the Vault OIDC setup script:
```bash
docker exec -it vault sh
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='<your-vault-token>'
export VAULT_OIDC_CLIENT_SECRET='<from-env>'
/vault/scripts/oidc-setup.sh
exit
```

4. Test Vault OIDC login:
   - Navigate to https://vault.local
   - Select "OIDC" as authentication method
   - Click "Sign in with OIDC Provider"
   - Login with Keycloak credentials

### Step 8: Restart Services

1. Restart coreservices:
```bash
cd /path/to/coreservices-homelab
docker-compose restart grafana
```

### Step 9: Test Authentication

Test each service:

1. **Grafana** (https://grafana.local)
   - Click "Sign in with Keycloak"
   - Login via Keycloak
   - Should access Grafana with appropriate role

2. **Vault** (https://vault.local)
   - Select "OIDC" method
   - Login via Keycloak
   - Should access Vault UI

3. **Protected Services**
   - Access the service URL
   - Should redirect to Keycloak
   - After login, should access the service

## Troubleshooting

### Keycloak Not Starting

```bash
# Check logs
docker-compose logs keycloak

# Common issues:
# - Database not ready: Wait longer or check auth-postgres logs
# - Port conflict: Ensure port 8085 is available
# - Memory: Increase KEYCLOAK_MEMORY_LIMIT in .env
```

### Cannot Access Keycloak Admin Console

```bash
# Verify Keycloak is running
docker-compose ps keycloak

# Check Traefik routing
curl -k https://auth.local/health/ready

# Verify /etc/hosts
grep auth.local /etc/hosts
```

### Client Secrets Not Working

```bash
# Regenerate client secret in Keycloak:
# 1. Login to admin console
# 2. Navigate to Clients > [client-name] > Credentials
# 3. Click "Regenerate Secret"
# 4. Copy new secret to .env
# 5. Restart affected service
```

### ForwardAuth Not Working

```bash
# Check ForwardAuth logs
docker-compose logs traefik-forward-auth

# Verify middleware is applied
docker-compose exec traefik cat /etc/traefik/dynamic.yml

# Test ForwardAuth directly
curl -v https://auth.local/oauth/callback
```

### Users Cannot Login

```bash
# Verify user exists in Keycloak
# Check user is in correct group
# Verify email is verified (if required)
# Check Keycloak logs for authentication errors
docker-compose logs keycloak | grep ERROR
```

## Post-Deployment

### Backup Keycloak Configuration

```bash
# Backup Keycloak database
docker exec auth-postgres pg_dump -U postgres keycloak > keycloak-backup.sql

# Backup Keycloak data volume
docker run --rm -v auth_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/keycloak-data.tar.gz /data
```

### Monitor Authentication

```bash
# View Keycloak logs
docker-compose logs -f keycloak

# View ForwardAuth logs
docker-compose logs -f traefik-forward-auth

# Check failed login attempts in Keycloak admin console:
# Realm Settings > Events > Login Events
```

### Update Keycloak

```bash
# Pull latest image
docker-compose pull keycloak

# Restart with new image
docker-compose up -d keycloak
```

## Security Recommendations

1. **Change Default Admin Password**: After initial setup, change the Keycloak admin password

2. **Enable MFA**: Configure TOTP/WebAuthn in Keycloak for additional security

3. **Review Session Settings**: Configure appropriate session timeouts in Keycloak

4. **Enable Audit Logging**: Configure Keycloak event logging for security monitoring

5. **Regular Backups**: Schedule regular backups of the auth-postgres database

6. **SSL Certificates**: For production, use Let's Encrypt instead of self-signed certificates

7. **Network Isolation**: Consider using Docker networks to isolate auth services

## Next Steps

- Configure email settings in Keycloak for password reset
- Set up social login providers (GitHub, Google, etc.)
- Implement fine-grained authorization policies
- Integrate with monitoring (Grafana dashboards for auth metrics)

## Support

For issues or questions:
- Review the full implementation plan: `docs/keycloak-implementation-plan.md`
- Check Keycloak documentation: https://www.keycloak.org/documentation
- Review service-specific OIDC documentation