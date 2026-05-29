# Setup.sh Check Functions Analysis

## Summary
- **Total check functions found:** 3 primary check functions
- **Categories:** Prerequisites, Dependencies, Validation
- **Script Location:** `../ai-stack-homelab/scripts/setup.sh`
- **Total Lines:** 547

## Check Functions

### 1. check_prerequisites
- **Purpose:** Validates that all required system prerequisites are available before setup
- **Location:** Lines 36-69
- **Called at:** Line 531 (in main function)
- **Dependencies:** 
  - `colima` command (optional)
  - `docker` command (required)
  - `docker-compose` command (required)
  - `df` command for disk space check
- **Checks Performed:**
  1. **Docker Runtime Availability** (Lines 40-48)
     - Checks if Colima is running: `colima status`
     - Falls back to checking Docker daemon: `docker info`
     - Exits with error if neither is available
  2. **Docker Compose Availability** (Lines 52-57)
     - Verifies Docker Compose is installed: `docker-compose version`
     - Exits with error if not available
  3. **Disk Space Check** (Lines 60-66)
     - Checks available disk space using `df -k`
     - Warns if less than 10GB available (10485760 KB)
     - Recommends at least 50GB for AI models and data
- **Exit Conditions:**
  - No Docker runtime available (exit code 1)
  - Docker Compose not available (exit code 1)
- **Notes:** 
  - Flexible Docker runtime detection (Colima or Docker Desktop)
  - Disk space check is a warning, not a blocker
  - Uses `> /dev/null 2>&1` to suppress command output

### 2. check_coreservices_available
- **Purpose:** Verifies that the coreservices-homelab dependency is present, running, and properly configured
- **Location:** Lines 71-110
- **Called at:** Line 532 (in main function)
- **Dependencies:**
  - `coreservices-homelab` directory at `../coreservices-homelab`
  - `docker-compose` command
  - Core services must be running
  - PKI infrastructure must be generated
- **Checks Performed:**
  1. **Core Services Directory Exists** (Lines 79-83)
     - Checks if `../coreservices-homelab` directory exists
     - Exits with error and instructions if not found
  2. **Core Services Running** (Lines 85-92)
     - Counts running containers: `docker-compose ps --services --filter status=running`
     - Requires at least 1 running container
     - Exits with error and start instructions if none running
  3. **CA Bundle Availability** (Lines 94-99)
     - Checks if `pki/client/ca_bundle.crt` exists and is not empty
     - Exits with error if missing or empty
  4. **Shared TLS Certificates** (Lines 101-106)
     - Verifies `pki/certs/cert.pem` exists
     - Verifies `pki/certs/key.pem` exists
     - Exits with error if either is missing
- **Exit Conditions:**
  - Core services directory not found (exit code 1)
  - No running core services containers (exit code 1)
  - CA bundle missing or empty (exit code 1)
  - Shared TLS certs missing (exit code 1)
- **Notes:**
  - Critical dependency check for the entire setup
  - Provides clear remediation steps in error messages
  - Uses `wc -l | tr -d ' '` to clean up container count output

### 3. is_url_safe_secret
- **Purpose:** Validates that a secret value contains only URL-safe characters
- **Location:** Lines 146-149
- **Called at:** Line 183 (within ensure_url_safe_secret function)
- **Dependencies:** None (pure bash regex)
- **Checks Performed:**
  1. **URL-Safe Character Validation** (Line 148)
     - Tests if value matches regex: `^[A-Za-z0-9._~-]+$`
     - Allows: letters, numbers, period, underscore, tilde, hyphen
     - Returns 0 (true) if valid, 1 (false) if invalid
- **Exit Conditions:** None (returns boolean result)
- **Notes:**
  - Helper function for secret validation
  - Used to ensure secrets can be safely used in URLs
  - Part of the secret rotation mechanism

## Supporting Validation Functions

### 4. setup_signal_cli_registry (Contains Registry Check)
- **Purpose:** Sets up Signal-CLI in local registry, includes registry availability check
- **Location:** Lines 392-449
- **Called at:** Line 538 (in main function)
- **Dependencies:**
  - Local registry running in coreservices-homelab
  - `docker-compose` command
  - `docker pull` and `docker push` commands
- **Checks Performed:**
  1. **Core Services Directory Check** (Lines 399-415)
     - Verifies `../coreservices-homelab` exists
     - Returns early with warning if not found
  2. **Registry Container Running** (Lines 401-409)
     - Checks if registry container is running: `docker-compose ps registry`
     - Uses `grep -q "Up"` to verify status
     - Returns with error if not running
  3. **Image Pull Success** (Lines 425-444)
     - Attempts to pull from GHCR
     - Returns with warning if pull fails
  4. **Image Push Success** (Lines 434-439)
     - Attempts to push to local registry
     - Returns with warning if push fails
- **Exit Conditions:** None (returns 1 on failure but doesn't exit script)
- **Notes:**
  - Non-blocking checks (uses return instead of exit)
  - Provides helpful error messages with remediation steps
  - Gracefully handles missing GHCR configuration

### 5. setup_models (Contains CPU Limit Check)
- **Purpose:** Sets up AI models, includes Docker CPU limit validation
- **Location:** Lines 469-503
- **Called at:** Line 540 (in main function)
- **Dependencies:**
  - `docker info` command
  - `awk` for numeric comparison
  - Ollama service
- **Checks Performed:**
  1. **Docker CPU Count** (Lines 472-478)
     - Gets available CPUs: `docker info --format '{{.NCPU}}'`
     - Compares OLLAMA_CPU_LIMIT against available CPUs
     - Caps OLLAMA_CPU_LIMIT if it exceeds available CPUs
- **Exit Conditions:** None (adjusts configuration instead)
- **Notes:**
  - Preventive check to avoid resource over-allocation
  - Automatically adjusts configuration rather than failing
  - Uses awk for floating-point comparison

## Helper Functions (Non-Check)

### render_env
- **Location:** Lines 112-144
- **Purpose:** Renders environment file with variable expansion
- **Not a check function:** Performs transformation, not validation

### upsert_env_var
- **Location:** Lines 151-176
- **Purpose:** Updates or inserts environment variable in file
- **Not a check function:** Performs file modification

### ensure_url_safe_secret
- **Location:** Lines 178-193
- **Purpose:** Ensures secrets are URL-safe, rotates if needed
- **Contains check:** Uses `is_url_safe_secret` internally

## Execution Flow

```
main()
  ├─> check_prerequisites()           [BLOCKING]
  ├─> check_coreservices_available()  [BLOCKING]
  ├─> setup_environment()
  ├─> setup_tls_certificates()
  ├─> setup_picoclaw_config()
  ├─> create_directories()
  ├─> create_configs()
  ├─> setup_signal_cli_registry()     [NON-BLOCKING CHECK]
  ├─> pull_images()
  ├─> setup_models()                  [NON-BLOCKING CHECK]
  ├─> setup_scripts()
  ├─> create_backup_script()
  └─> show_completion()
```

## Check Categories

### 1. System Prerequisites (Blocking)
- Docker runtime availability
- Docker Compose availability
- Disk space warning

### 2. Dependency Checks (Blocking)
- Core services directory exists
- Core services containers running
- PKI infrastructure present
- TLS certificates available

### 3. Validation Checks (Non-Blocking)
- URL-safe secret validation
- Registry availability
- Docker CPU limits

### 4. Runtime Checks (Non-Blocking)
- Image pull/push success
- Model download success

## Recommendations

### 1. Consolidation Opportunities
- **Create a unified validation framework:**
  - Extract common check patterns (directory exists, file exists, service running)
  - Create reusable check functions with consistent error handling
  - Example: `check_directory_exists()`, `check_file_exists()`, `check_service_running()`

### 2. Improve Error Handling
- **Standardize exit codes:**
  - 1: Missing prerequisites
  - 2: Missing dependencies
  - 3: Configuration errors
  - 4: Runtime errors
- **Add retry logic** for transient failures (network, service startup)

### 3. Enhanced Validation
- **Add version checks:**
  - Docker version compatibility
  - Docker Compose version compatibility
  - Minimum macOS version
- **Add network connectivity checks:**
  - Internet connectivity for image pulls
  - Local network for registry access
  - DNS resolution

### 4. Logging Improvements
- **Add verbose mode** for debugging
- **Log all checks to file** for troubleshooting
- **Add timestamps** to check outputs
- **Create summary report** of all checks at the end

### 5. Modularization
- **Extract check functions to separate file:**
  - `scripts/lib/checks.sh` - All check functions
  - `scripts/lib/utils.sh` - Helper functions
  - Source these in main setup.sh
- **Benefits:**
  - Easier testing
  - Reusable across scripts
  - Better maintainability

### 6. Add Pre-flight Check Mode
- **Create `--check-only` flag:**
  - Run all checks without making changes
  - Generate detailed report
  - Exit with status code indicating readiness

### 7. Specific Function Improvements

#### check_prerequisites
- Add Docker version check (minimum required version)
- Check for required Docker features (BuildKit, etc.)
- Validate network connectivity before proceeding

#### check_coreservices_available
- Add timeout for service checks
- Verify specific services are running (not just count)
- Check service health endpoints if available

#### setup_signal_cli_registry
- Add retry logic for image pulls
- Verify image integrity after pull
- Check registry disk space before push

### 8. Testing Recommendations
- Create unit tests for check functions
- Add integration tests for full setup flow
- Mock external dependencies for testing
- Add CI/CD pipeline to run tests

## Potential Issues

### 1. Race Conditions
- **Issue:** Core services might be starting but not fully ready
- **Solution:** Add health check polling with timeout

### 2. Silent Failures
- **Issue:** Some checks return instead of exit, might be missed
- **Solution:** Collect all warnings and display summary

### 3. Disk Space Check
- **Issue:** Only checks current directory, not Docker volumes
- **Solution:** Check Docker volume storage location

### 4. CPU Limit Check
- **Issue:** Only checks total CPUs, not available CPUs
- **Solution:** Check current Docker resource allocation

## Conclusion

The setup.sh script has a solid foundation of check functions covering critical prerequisites and dependencies. The main strengths are:
- Clear separation of blocking vs. non-blocking checks
- Helpful error messages with remediation steps
- Flexible Docker runtime detection

Key areas for improvement:
- Consolidate common check patterns
- Add more comprehensive validation
- Improve error handling and logging
- Modularize for better maintainability

The script follows a fail-fast approach for critical checks while being lenient with optional features, which is appropriate for a setup script.