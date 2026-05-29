# Task 001: Consolidate Check Functions into Reusable Library

## Overview
Extract and consolidate common check patterns from `setup.sh` into a reusable library file to improve maintainability, testability, and code reuse across scripts.

## Objectives
1. Create a new library file `scripts/lib/checks.sh` with reusable check functions
2. Refactor existing check functions in `setup.sh` to use the library
3. Ensure backward compatibility with existing functionality
4. Add consistent error handling and exit codes

## Scope

### In Scope
- Extract common check patterns from `setup.sh`
- Create standardized check functions
- Update `setup.sh` to source and use the library
- Maintain all existing functionality
- Add inline documentation

### Out of Scope
- Adding new checks not currently in setup.sh
- Logging integration (covered in Task 002)
- Retry logic implementation
- Version compatibility checks

## Detailed Requirements

### 1. Create Library Structure

**File:** `scripts/lib/checks.sh`

**Required Functions:**

#### System Checks
```bash
check_command_exists()
  - Parameters: command_name, friendly_name (optional)
  - Returns: 0 if exists, 1 if not
  - Example: check_command_exists "docker" "Docker"

check_service_running()
  - Parameters: service_name, check_command
  - Returns: 0 if running, 1 if not
  - Example: check_service_running "Docker" "docker info"

check_disk_space()
  - Parameters: path, minimum_kb, warning_only (boolean)
  - Returns: 0 if sufficient, 1 if not (or 0 if warning_only)
  - Example: check_disk_space "." 10485760 true
```

#### File/Directory Checks
```bash
check_directory_exists()
  - Parameters: path, error_message (optional)
  - Returns: 0 if exists, 1 if not
  - Example: check_directory_exists "../coreservices-homelab"

check_file_exists()
  - Parameters: path, error_message (optional)
  - Returns: 0 if exists, 1 if not
  - Example: check_file_exists "pki/certs/cert.pem"

check_file_not_empty()
  - Parameters: path, error_message (optional)
  - Returns: 0 if not empty, 1 if empty or missing
  - Example: check_file_not_empty "pki/client/ca_bundle.crt"
```

#### Container/Docker Checks
```bash
check_docker_runtime()
  - Parameters: none
  - Returns: 0 if Docker available, 1 if not
  - Checks: Colima or Docker daemon

check_docker_compose()
  - Parameters: none
  - Returns: 0 if available, 1 if not

check_container_running()
  - Parameters: compose_path, service_name (optional)
  - Returns: 0 if running, count of running containers
  - Example: check_container_running "../coreservices-homelab"

check_docker_cpu_limit()
  - Parameters: requested_cpus
  - Returns: available_cpus (capped to actual available)
  - Example: check_docker_cpu_limit "$OLLAMA_CPU_LIMIT"
```

#### Validation Checks
```bash
is_url_safe_string()
  - Parameters: value
  - Returns: 0 if URL-safe, 1 if not
  - Pattern: ^[A-Za-z0-9._~-]+$

validate_secret()
  - Parameters: var_name, hex_bytes
  - Returns: 0 (always), rotates if needed
  - Side effect: Updates .env files
```

### 2. Standardized Error Handling

**Exit Codes:**
```bash
EXIT_SUCCESS=0
EXIT_PREREQ_MISSING=1
EXIT_DEPENDENCY_MISSING=2
EXIT_CONFIG_ERROR=3
EXIT_RUNTIME_ERROR=4
```

**Error Message Format:**
```bash
print_error()
  - Parameters: message, exit_code (optional)
  - Format: "❌ [ERROR] message"
  - Exits if exit_code provided

print_warning()
  - Parameters: message
  - Format: "⚠️  [WARNING] message"

print_success()
  - Parameters: message
  - Format: "✅ [SUCCESS] message"

print_info()
  - Parameters: message
  - Format: "ℹ️  [INFO] message"
```

### 3. Refactor setup.sh

**Changes Required:**

1. **Add library sourcing** (after line 23):
```bash
# Source check library
SCRIPT_LIB_DIR="${PROJECT_ROOT}/scripts/lib"
if [ -f "${SCRIPT_LIB_DIR}/checks.sh" ]; then
    source "${SCRIPT_LIB_DIR}/checks.sh"
else
    echo "❌ Required library not found: ${SCRIPT_LIB_DIR}/checks.sh"
    exit 1
fi
```

2. **Refactor check_prerequisites** (lines 36-69):
```bash
check_prerequisites() {
    print_section "📋 Checking Prerequisites"
    
    # Check Docker runtime
    if ! check_docker_runtime; then
        print_error "No Docker runtime available. Start Docker Desktop or Colima and try again" $EXIT_PREREQ_MISSING
    fi
    print_success "Docker daemon is available"
    
    # Check Docker Compose
    if ! check_docker_compose; then
        print_error "Docker Compose not available. Please update Docker Desktop to the latest version" $EXIT_PREREQ_MISSING
    fi
    print_success "Docker Compose is available"
    
    # Check disk space
    check_disk_space "." 10485760 true
    
    echo ""
}
```

3. **Refactor check_coreservices_available** (lines 71-110):
```bash
check_coreservices_available() {
    print_section "🔗 Checking Core Services Dependency"
    
    local core_root="${PROJECT_ROOT}/../coreservices-homelab"
    local core_ca_bundle="${core_root}/pki/client/ca_bundle.crt"
    local core_certs_dir="${core_root}/pki/certs"
    
    # Check directory exists
    if ! check_directory_exists "$core_root"; then
        print_error "Core services folder not found: $core_root\nClone/place coreservices-homelab next to ai-stack-homelab and retry" $EXIT_DEPENDENCY_MISSING
    fi
    
    # Check containers running
    local running_count
    running_count=$(check_container_running "$core_root")
    if [ "$running_count" -lt 1 ]; then
        print_error "No running core services containers found\nStart core services first: cd ../coreservices-homelab && ./scripts/start.sh" $EXIT_DEPENDENCY_MISSING
    fi
    print_success "Core services are running (${running_count} container(s))"
    
    # Check CA bundle
    if ! check_file_not_empty "$core_ca_bundle"; then
        print_error "Core root CA bundle not found or empty: $core_ca_bundle\nGenerate PKI first in core services, then re-run setup" $EXIT_DEPENDENCY_MISSING
    fi
    print_success "Core CA bundle is available: $core_ca_bundle"
    
    # Check TLS certs
    if ! check_file_exists "$core_certs_dir/cert.pem" || ! check_file_exists "$core_certs_dir/key.pem"; then
        print_error "Core shared TLS certs missing under: $core_certs_dir\nRun core setup first to generate shared certs" $EXIT_DEPENDENCY_MISSING
    fi
    print_success "Core shared TLS certs are available: $core_certs_dir"
    
    print_success "Core services workspace is available"
    echo ""
}
```

4. **Update ensure_url_safe_secret** (lines 178-193):
```bash
ensure_url_safe_secret() {
    local var_name="$1"
    local hex_bytes="$2"
    
    validate_secret "$var_name" "$hex_bytes"
}
```

5. **Update setup_models CPU check** (lines 472-478):
```bash
setup_models() {
    print_section "🤖 Setting Up AI Models"
    
    # Check and cap CPU limit
    if [ -n "${OLLAMA_CPU_LIMIT:-}" ]; then
        OLLAMA_CPU_LIMIT=$(check_docker_cpu_limit "$OLLAMA_CPU_LIMIT")
        export OLLAMA_CPU_LIMIT
    fi
    
    # ... rest of function
}
```

## Implementation Steps

### Phase 1: Create Library (Day 1)
1. Create `scripts/lib/` directory
2. Create `scripts/lib/checks.sh` with all functions
3. Add comprehensive inline documentation
4. Add unit tests (optional but recommended)

### Phase 2: Refactor setup.sh (Day 2)
1. Add library sourcing
2. Refactor check_prerequisites
3. Refactor check_coreservices_available
4. Update helper functions
5. Test all functionality

### Phase 3: Testing (Day 3)
1. Test with Docker Desktop
2. Test with Colima
3. Test error conditions
4. Test with missing dependencies
5. Verify all exit codes

### Phase 4: Documentation (Day 3)
1. Update setup.sh comments
2. Add library usage documentation
3. Update README if needed

## Testing Requirements

### Unit Tests
- Test each check function independently
- Mock external commands (docker, colima, etc.)
- Test all return codes
- Test error messages

### Integration Tests
- Run full setup.sh with library
- Test with various Docker configurations
- Test failure scenarios
- Verify backward compatibility

### Test Cases
1. ✅ Docker Desktop running
2. ✅ Colima running
3. ❌ No Docker runtime
4. ❌ Docker Compose missing
5. ⚠️  Low disk space
6. ❌ Core services not found
7. ❌ Core services not running
8. ❌ PKI not generated
9. ✅ All checks pass

## Success Criteria
- [ ] Library file created with all required functions
- [ ] setup.sh successfully refactored
- [ ] All existing functionality preserved
- [ ] All tests pass
- [ ] Code is more maintainable and readable
- [ ] Error messages are consistent and helpful
- [ ] Exit codes are standardized
- [ ] Documentation is complete

## Dependencies
- None (standalone task)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing functionality | High | Comprehensive testing, backward compatibility checks |
| Library not found at runtime | High | Add existence check before sourcing |
| Performance degradation | Low | Keep functions lightweight, avoid unnecessary calls |
| Inconsistent behavior across environments | Medium | Test on multiple systems (macOS, Linux if applicable) |

## Deliverables
1. `scripts/lib/checks.sh` - Reusable check library
2. Updated `setup.sh` - Refactored to use library
3. Test results - Documentation of all test cases
4. Usage documentation - How to use the library in other scripts

## Future Enhancements (Not in Scope)
- Add retry logic to check functions
- Add timeout parameters
- Create additional libraries (utils.sh, logging.sh)
- Add version compatibility checks
- Implement health check polling

## Notes
- Maintain backward compatibility at all costs
- Keep functions simple and focused
- Use consistent naming conventions
- Add comments for complex logic
- Consider making library reusable in other scripts (start.sh, stop.sh, etc.)

## Related Tasks
- Task 002: Add comprehensive logging with timestamps