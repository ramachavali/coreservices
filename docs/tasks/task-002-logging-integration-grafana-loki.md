# Task 002: Add Comprehensive Logging with Timestamps to Grafana/Loki

## Overview
Implement comprehensive structured logging for setup.sh and other management scripts with integration to Grafana/Loki for centralized log aggregation, analysis, and monitoring.

## Objectives
1. Create a logging library that sends logs to both stdout and Loki
2. Add structured logging with timestamps, log levels, and metadata
3. Configure Grafana dashboards for script execution monitoring
4. Enable log retention and querying capabilities
5. Provide real-time visibility into setup and operational tasks

## Scope

### In Scope
- Create logging library (`scripts/lib/logging.sh`)
- Integrate logging into setup.sh and other scripts
- Configure Loki to receive script logs
- Create Grafana dashboards for script monitoring
- Add log retention policies
- Document logging architecture

### Out of Scope
- Application-level logging (containers handle their own)
- Log shipping from other systems
- Advanced alerting rules (future enhancement)
- Log encryption at rest
- Multi-tenant logging

## Architecture

### Logging Flow
```
Script Execution
    ↓
logging.sh Library
    ↓
    ├─→ stdout/stderr (console output)
    └─→ Promtail/Alloy (log collector)
            ↓
        Loki (log aggregation)
            ↓
        Grafana (visualization)
```

### Log Format (JSON)
```json
{
  "timestamp": "2026-05-29T23:00:00.000Z",
  "level": "INFO",
  "script": "setup.sh",
  "function": "check_prerequisites",
  "message": "Docker daemon is available",
  "host": "mac-mini-m4",
  "user": "rama",
  "pid": 12345,
  "execution_id": "uuid-v4",
  "metadata": {
    "check_type": "docker_runtime",
    "duration_ms": 150
  }
}
```

## Detailed Requirements

### 1. Create Logging Library

**File:** `scripts/lib/logging.sh`

#### Core Functions

```bash
# Initialize logging for a script
init_logging()
  - Parameters: script_name
  - Sets up: execution_id, log file, Loki endpoint
  - Returns: 0 on success
  - Example: init_logging "setup.sh"

# Log with level and metadata
log_message()
  - Parameters: level, message, metadata (optional JSON)
  - Levels: DEBUG, INFO, WARN, ERROR, FATAL
  - Sends to: stdout + Loki
  - Example: log_message "INFO" "Check passed" '{"check":"docker"}'

# Convenience functions
log_debug()    # Debug level
log_info()     # Info level
log_warn()     # Warning level
log_error()    # Error level
log_fatal()    # Fatal level (exits script)

# Structured logging for checks
log_check_start()
  - Parameters: check_name, check_type
  - Records: start time, check metadata
  - Example: log_check_start "Docker Runtime" "prerequisite"

log_check_end()
  - Parameters: check_name, status (pass/fail), details
  - Records: end time, duration, result
  - Example: log_check_end "Docker Runtime" "pass" "Docker Desktop running"

# Performance tracking
log_duration()
  - Parameters: operation_name, start_time, end_time
  - Calculates: duration in milliseconds
  - Example: log_duration "image_pull" "$start" "$end"

# Cleanup
finalize_logging()
  - Flushes: any pending logs
  - Sends: execution summary to Loki
  - Example: finalize_logging
```

#### Configuration

```bash
# Environment variables
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://localhost:3100}"
LOKI_ENABLED="${LOKI_ENABLED:-true}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"
LOG_FILE_PATH="${LOG_FILE_PATH:-logs/scripts}"
```

### 2. Loki Integration

#### Send Logs to Loki

```bash
send_to_loki() {
    local timestamp="$1"
    local level="$2"
    local message="$3"
    local metadata="$4"
    
    if [ "$LOKI_ENABLED" != "true" ]; then
        return 0
    fi
    
    local log_entry
    log_entry=$(cat <<EOF
{
  "streams": [
    {
      "stream": {
        "job": "homelab-scripts",
        "script": "${SCRIPT_NAME}",
        "level": "${level}",
        "host": "${HOSTNAME}",
        "environment": "homelab"
      },
      "values": [
        [
          "${timestamp}000000",
          $(jq -n \
            --arg ts "$timestamp" \
            --arg lvl "$level" \
            --arg script "$SCRIPT_NAME" \
            --arg func "${CURRENT_FUNCTION:-main}" \
            --arg msg "$message" \
            --arg host "$HOSTNAME" \
            --arg user "$USER" \
            --arg pid "$$" \
            --arg exec_id "$EXECUTION_ID" \
            --argjson meta "${metadata:-{}}" \
            '{
              timestamp: $ts,
              level: $lvl,
              script: $script,
              function: $func,
              message: $msg,
              host: $host,
              user: $user,
              pid: $pid,
              execution_id: $exec_id,
              metadata: $meta
            }')
        ]
      ]
    }
  ]
}
EOF
)
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$log_entry" \
        "${LOKI_ENDPOINT}/loki/api/v1/push" \
        > /dev/null 2>&1 || true
}
```

### 3. Update Loki Configuration

**File:** `configs/loki/loki-config.yaml`

Add script logs retention and indexing:

```yaml
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
      # Add script logs index
    - from: 2026-05-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: script_logs_
        period: 24h

limits_config:
  # Script logs retention
  retention_period: 720h  # 30 days
  
  # Per-stream limits
  per_stream_rate_limit: 5MB
  per_stream_rate_limit_burst: 10MB

# Table manager for retention
table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
```

### 4. Configure Alloy/Promtail for Script Logs

**File:** `configs/alloy/config.alloy`

Add file-based log collection:

```hcl
// Script logs collection
loki.source.file "script_logs" {
  targets = [
    {
      __path__ = "/var/log/homelab/scripts/*.log",
      job      = "homelab-scripts",
      host     = env("HOSTNAME"),
    },
  ]
  
  forward_to = [loki.write.default.receiver]
}

// Add JSON parsing for structured logs
loki.process "script_logs_json" {
  forward_to = [loki.write.default.receiver]
  
  stage.json {
    expressions = {
      level        = "level",
      script       = "script",
      function     = "function",
      execution_id = "execution_id",
    }
  }
  
  stage.labels {
    values = {
      level        = "",
      script       = "",
      execution_id = "",
    }
  }
}
```

### 5. Create Grafana Dashboard

**File:** `configs/grafana/provisioning/dashboards/script-monitoring.json`

Dashboard panels:
1. **Script Executions Timeline** - Show all script runs
2. **Check Success Rate** - Pass/fail ratio for checks
3. **Execution Duration** - Time taken per script
4. **Error Rate** - Errors over time
5. **Recent Failures** - Last 10 failed checks
6. **Active Executions** - Currently running scripts
7. **Check Performance** - Duration by check type
8. **Log Volume** - Logs per script over time

Example queries:
```logql
# All script executions
{job="homelab-scripts"} | json

# Failed checks
{job="homelab-scripts", level="ERROR"} | json | line_format "{{.message}}"

# Execution duration
sum by (script) (
  rate({job="homelab-scripts"} | json | unwrap duration_ms [5m])
)

# Check success rate
sum by (check_type) (
  count_over_time({job="homelab-scripts"} | json | metadata_check_type != "" [1h])
) / ignoring(status) group_left
sum by (check_type) (
  count_over_time({job="homelab-scripts", level="ERROR"} | json | metadata_check_type != "" [1h])
)
```

### 6. Update setup.sh with Logging

**Changes Required:**

1. **Add logging initialization** (after library sourcing):
```bash
# Initialize logging
init_logging "setup.sh"
trap finalize_logging EXIT
```

2. **Update check_prerequisites**:
```bash
check_prerequisites() {
    print_section "📋 Checking Prerequisites"
    log_info "Starting prerequisites check"
    
    # Check Docker runtime
    log_check_start "docker_runtime" "prerequisite"
    local start_time=$(date +%s%3N)
    
    if ! check_docker_runtime; then
        log_check_end "docker_runtime" "fail" "No Docker runtime available"
        print_error "No Docker runtime available" $EXIT_PREREQ_MISSING
    fi
    
    local end_time=$(date +%s%3N)
    log_check_end "docker_runtime" "pass" "Docker daemon is available"
    log_duration "docker_runtime_check" "$start_time" "$end_time"
    print_success "Docker daemon is available"
    
    # ... similar for other checks
}
```

3. **Add execution summary**:
```bash
finalize_logging() {
    local end_time=$(date +%s%3N)
    local duration=$((end_time - SCRIPT_START_TIME))
    
    log_info "Setup completed" "{\"duration_ms\": $duration, \"status\": \"success\"}"
}
```

### 7. Docker Compose Updates

**File:** `docker-compose.yml` (in coreservices-homelab)

Ensure Loki and Alloy are configured:

```yaml
services:
  loki:
    # ... existing config
    volumes:
      - loki_data:/loki
      - ./configs/loki/loki-config.yaml:/etc/loki/loki-config.yaml
      - /var/log/homelab:/var/log/homelab:ro  # Mount script logs
    
  alloy:
    # ... existing config
    volumes:
      - ./configs/alloy/config.alloy:/etc/alloy/config.alloy
      - /var/log/homelab:/var/log/homelab:ro  # Mount script logs
    
  grafana:
    # ... existing config
    volumes:
      - grafana_data:/var/lib/grafana
      - ./configs/grafana/provisioning:/etc/grafana/provisioning
```

## Implementation Steps

### Phase 1: Logging Library (Week 1)
1. Create `scripts/lib/logging.sh`
2. Implement core logging functions
3. Add Loki integration
4. Add file-based logging
5. Test logging functions independently

### Phase 2: Loki Configuration (Week 1)
1. Update Loki config for script logs
2. Configure retention policies
3. Add log volume mounts
4. Test Loki ingestion

### Phase 3: Alloy/Promtail Setup (Week 1)
1. Configure file-based log collection
2. Add JSON parsing
3. Test log shipping to Loki
4. Verify labels and metadata

### Phase 4: Script Integration (Week 2)
1. Update setup.sh with logging
2. Add logging to start.sh
3. Add logging to stop.sh
4. Add logging to other management scripts
5. Test all scripts with logging

### Phase 5: Grafana Dashboards (Week 2)
1. Create script monitoring dashboard
2. Add panels for key metrics
3. Configure alerts (optional)
4. Test dashboard queries
5. Document dashboard usage

### Phase 6: Documentation (Week 2)
1. Document logging architecture
2. Create logging usage guide
3. Add troubleshooting section
4. Update runbooks with logging info

## Testing Requirements

### Unit Tests
- Test each logging function
- Test Loki payload generation
- Test timestamp formatting
- Test metadata handling

### Integration Tests
- Test end-to-end log flow
- Verify logs appear in Grafana
- Test log retention
- Test high-volume logging

### Test Scenarios
1. ✅ Log to stdout only (Loki disabled)
2. ✅ Log to Loki only
3. ✅ Log to both stdout and Loki
4. ✅ Handle Loki unavailable gracefully
5. ✅ Log structured metadata
6. ✅ Query logs in Grafana
7. ✅ Verify log retention
8. ✅ Test concurrent script execution

## Success Criteria
- [ ] Logging library created and functional
- [ ] All scripts integrated with logging
- [ ] Logs visible in Grafana
- [ ] Dashboards created and working
- [ ] Log retention configured
- [ ] Performance impact < 5% on script execution
- [ ] Documentation complete
- [ ] No log loss during normal operations

## Dependencies
- Task 001 (check functions library) - Recommended but not required
- Loki running in coreservices-homelab
- Grafana running in coreservices-homelab
- Alloy/Promtail configured

## Performance Considerations

### Optimization Strategies
1. **Async Logging**: Send to Loki in background
2. **Batching**: Batch multiple log entries
3. **Buffering**: Buffer logs and flush periodically
4. **Fallback**: Gracefully handle Loki unavailable
5. **Sampling**: Sample high-frequency logs if needed

### Expected Impact
- Script execution overhead: < 5%
- Network traffic: ~1-5 KB per script execution
- Disk usage: ~100 MB per month (with 30-day retention)
- Loki CPU: < 5% increase
- Loki Memory: < 100 MB increase

## Security Considerations

### Sensitive Data Handling
1. **Redact secrets** from logs
2. **Mask passwords** in error messages
3. **Filter environment variables** before logging
4. **Sanitize file paths** that may contain usernames

### Implementation
```bash
sanitize_log_message() {
    local message="$1"
    
    # Redact common secret patterns
    message=$(echo "$message" | sed -E 's/(password|token|key|secret)=[^ ]*/\1=***REDACTED***/gi')
    message=$(echo "$message" | sed -E 's/Bearer [^ ]*/Bearer ***REDACTED***/gi')
    
    echo "$message"
}
```

## Monitoring and Alerts

### Key Metrics to Track
1. Script execution count
2. Script failure rate
3. Average execution duration
4. Check failure rate by type
5. Log ingestion rate
6. Log storage usage

### Recommended Alerts
1. Script execution failure (ERROR level)
2. Check failure rate > 10%
3. Script execution time > 2x baseline
4. Log ingestion stopped
5. Loki storage > 80% full

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Loki unavailable | Medium | Fallback to file-only logging |
| Log volume too high | Medium | Implement sampling and retention |
| Performance degradation | Low | Async logging, batching |
| Sensitive data in logs | High | Implement sanitization |
| Disk space exhaustion | Medium | Configure retention, monitoring |
| Network issues | Low | Buffer logs, retry logic |

## Deliverables
1. `scripts/lib/logging.sh` - Logging library
2. Updated `setup.sh` - With logging integration
3. Updated management scripts - With logging
4. `configs/loki/loki-config.yaml` - Updated config
5. `configs/alloy/config.alloy` - Updated config
6. `configs/grafana/provisioning/dashboards/script-monitoring.json` - Dashboard
7. `docs/logging-architecture.md` - Architecture documentation
8. `docs/logging-usage-guide.md` - Usage guide

## Future Enhancements (Not in Scope)
- Real-time alerting via Signal/Slack
- Log-based anomaly detection
- Automated remediation based on logs
- Log correlation with container logs
- Advanced log analytics (ML-based)
- Multi-environment log aggregation
- Log-based SLA tracking

## Example Usage

```bash
#!/bin/bash
source "$(dirname "$0")/lib/logging.sh"
source "$(dirname "$0")/lib/checks.sh"

# Initialize logging
init_logging "my-script.sh"
trap finalize_logging EXIT

# Log a simple message
log_info "Starting my script"

# Log with metadata
log_info "Processing item" '{"item_id": 123, "type": "user"}'

# Log a check
log_check_start "database_connection" "dependency"
if check_database_connection; then
    log_check_end "database_connection" "pass" "Connected successfully"
else
    log_check_end "database_connection" "fail" "Connection timeout"
    log_error "Failed to connect to database"
    exit 1
fi

# Log duration
start=$(date +%s%3N)
perform_operation
end=$(date +%s%3N)
log_duration "operation" "$start" "$end"

log_info "Script completed successfully"
```

## Related Tasks
- Task 001: Consolidate check functions into reusable library
- Future: Add alerting integration
- Future: Implement log-based metrics

## Notes
- Keep logging lightweight to avoid performance impact
- Ensure logs don't contain sensitive information
- Test with Loki unavailable to ensure graceful degradation
- Consider log volume and retention costs
- Document log query patterns for common troubleshooting scenarios