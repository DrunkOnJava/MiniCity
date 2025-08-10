#!/bin/bash

# Claude Code Runner - Intelligent Build & Debug System
# Automatically detects and handles crashes/breakpoints for Claude Code
# =============================================================================

set -euo pipefail

# Configuration
PROJECT_DIR="/Users/griffin/Projects/MiniCity/MiniCity"
MONITOR_DIR="/tmp/minicity_monitor"
MONITOR_SCRIPT="$PROJECT_DIR/scripts/monitoring/crash_monitor.sh"
DIAGNOSTIC_SCRIPT="$PROJECT_DIR/scripts/monitoring/claude_diagnostic.sh"
BUILD_LOG="$PROJECT_DIR/build/last_build.log"
DIAGNOSTIC_LOG="$PROJECT_DIR/build/last_diagnostic.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ensure directories exist
mkdir -p "$PROJECT_DIR/build"
mkdir -p "$MONITOR_DIR"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    
    # Kill monitor if running
    if [[ -n "${MONITOR_PID:-}" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    exit "${1:-0}"
}

trap cleanup EXIT INT TERM

# Start the crash monitor in background
start_monitor() {
    echo -e "${BLUE}Starting crash monitor...${NC}"
    
    # Make scripts executable
    chmod +x "$MONITOR_SCRIPT"
    chmod +x "$DIAGNOSTIC_SCRIPT"
    
    # Start monitor in background
    "$MONITOR_SCRIPT" > "$MONITOR_DIR/monitor.log" 2>&1 &
    MONITOR_PID=$!
    
    # Wait for monitor to initialize
    sleep 2
    
    if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo -e "${RED}Failed to start monitor${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Monitor started (PID: $MONITOR_PID)${NC}"
    return 0
}

# Build the project
build_project() {
    echo -e "${BLUE}Building MiniCity...${NC}"
    
    cd "$PROJECT_DIR"
    
    # Capture build output
    if make build 2>&1 | tee "$BUILD_LOG"; then
        echo -e "${GREEN}Build successful${NC}"
        return 0
    else
        echo -e "${RED}Build failed${NC}"
        
        # Extract build errors
        local errors=$(grep -E "error:|Error:" "$BUILD_LOG" | head -10)
        
        # Generate diagnostic for Claude Code
        cat > "$DIAGNOSTIC_LOG" <<EOF
{
    "event": "build_failed",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "errors": $(echo "$errors" | jq -Rs 'split("\n") | map(select(length > 0))'),
    "suggested_fixes": [
        "Check Swift syntax errors",
        "Verify import statements",
        "Ensure all files are included in target",
        "Check for missing dependencies"
    ],
    "build_log": "$BUILD_LOG"
}
EOF
        
        echo "CLAUDE_CODE_BUILD_FAILED: $(cat "$DIAGNOSTIC_LOG" | jq -c .)"
        return 1
    fi
}

# Run the app and monitor for issues
run_with_monitoring() {
    echo -e "${BLUE}Launching MiniCity with monitoring...${NC}"
    
    cd "$PROJECT_DIR"
    
    # Start the app
    make run 2>&1 | tee -a "$BUILD_LOG" &
    local RUN_PID=$!
    
    # Wait for app to start
    sleep 5
    
    # Monitor for crashes/issues
    local crash_count=0
    local last_status="unknown"
    local stable_count=0
    
    while true; do
        # Check if make run is still running
        if ! kill -0 "$RUN_PID" 2>/dev/null; then
            echo -e "${YELLOW}Build/run process ended${NC}"
            break
        fi
        
        # Get current status
        local status="unknown"
        if [[ -f "$MONITOR_DIR/current_status.json" ]]; then
            status=$(jq -r '.status' "$MONITOR_DIR/current_status.json" 2>/dev/null || echo "unknown")
        fi
        
        # Check for state changes
        if [[ "$status" != "$last_status" ]]; then
            echo -e "${CYAN}Status changed: $last_status -> $status${NC}"
            last_status="$status"
            stable_count=0
            
            case "$status" in
                "crashed")
                    crash_count=$((crash_count + 1))
                    echo -e "${RED}CRASH DETECTED (#$crash_count)${NC}"
                    
                    # Get diagnostics
                    "$DIAGNOSTIC_SCRIPT" diagnose > "$DIAGNOSTIC_LOG"
                    
                    # Output for Claude Code
                    echo "CLAUDE_CODE_CRASH: $(cat "$DIAGNOSTIC_LOG" | jq -c .)"
                    
                    # Auto-recovery attempt
                    if [[ $crash_count -lt 3 ]]; then
                        echo -e "${YELLOW}Attempting auto-recovery...${NC}"
                        sleep 2
                        cd "$PROJECT_DIR" && make run 2>&1 | tee -a "$BUILD_LOG" &
                        RUN_PID=$!
                    else
                        echo -e "${RED}Multiple crashes detected - manual intervention required${NC}"
                        break
                    fi
                    ;;
                    
                "running")
                    echo -e "${GREEN}App is running normally${NC}"
                    stable_count=0
                    ;;
                    
                "not_running")
                    echo -e "${YELLOW}App is not running${NC}"
                    # Check if this is expected or a crash
                    if [[ -f "$MONITOR_DIR/last_crash.json" ]]; then
                        local crash_time=$(jq -r '.timestamp' "$MONITOR_DIR/last_crash.json" 2>/dev/null)
                        local current_time=$(date -u +"%s")
                        local crash_epoch=$(date -d "$crash_time" +"%s" 2>/dev/null || echo 0)
                        
                        if [[ $((current_time - crash_epoch)) -lt 10 ]]; then
                            echo -e "${RED}Recent crash detected${NC}"
                            status="crashed"
                        fi
                    fi
                    ;;
            esac
        else
            stable_count=$((stable_count + 1))
        fi
        
        # If stable for a while, consider it successful
        if [[ "$status" == "running" ]] && [[ $stable_count -gt 10 ]]; then
            echo -e "${GREEN}App is stable and running successfully${NC}"
            
            # Generate success report
            cat > "$DIAGNOSTIC_LOG" <<EOF
{
    "event": "run_successful",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status": "stable",
    "runtime": "$stable_count seconds",
    "crashes": $crash_count,
    "monitoring_active": true
}
EOF
            
            echo "CLAUDE_CODE_SUCCESS: $(cat "$DIAGNOSTIC_LOG" | jq -c .)"
            
            # Continue monitoring but less frequently
            sleep 5
            stable_count=$((stable_count + 5))
        else
            sleep 1
        fi
        
        # Timeout after 2 minutes
        if [[ $stable_count -gt 120 ]]; then
            echo -e "${GREEN}App has been stable for 2 minutes - monitoring complete${NC}"
            break
        fi
    done
    
    # Final status
    echo -e "${BLUE}Final diagnostic report:${NC}"
    "$DIAGNOSTIC_SCRIPT" diagnose
}

# Main execution flow
main() {
    echo -e "${CYAN}=== Claude Code Intelligent Runner ===${NC}"
    echo -e "${BLUE}Project: MiniCity${NC}"
    echo -e "${BLUE}Mode: Automated Debug & Recovery${NC}"
    echo ""
    
    # Start the monitor
    if ! start_monitor; then
        echo -e "${RED}Failed to start monitoring system${NC}"
        cleanup 1
    fi
    
    # Build the project
    if ! build_project; then
        echo -e "${RED}Build failed - check diagnostics${NC}"
        cleanup 1
    fi
    
    # Run with monitoring
    run_with_monitoring
    
    # Generate final report
    echo -e "${BLUE}Generating final report...${NC}"
    
    local final_status="unknown"
    if [[ -f "$MONITOR_DIR/current_status.json" ]]; then
        final_status=$(jq -r '.status' "$MONITOR_DIR/current_status.json" 2>/dev/null || echo "unknown")
    fi
    
    cat > "$DIAGNOSTIC_LOG" <<EOF
{
    "event": "run_complete",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "final_status": "$final_status",
    "build_log": "$BUILD_LOG",
    "diagnostic_files": [
        "$MONITOR_DIR/current_status.json",
        "$MONITOR_DIR/last_crash.json",
        "$MONITOR_DIR/metal_diagnostics.json"
    ],
    "success": $([ "$final_status" == "running" ] && echo "true" || echo "false")
}
EOF
    
    echo "CLAUDE_CODE_COMPLETE: $(cat "$DIAGNOSTIC_LOG" | jq -c .)"
    
    # Cleanup
    cleanup 0
}

# Run main function
main "$@"
