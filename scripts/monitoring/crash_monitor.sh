#!/bin/bash

# MiniCity Crash & Debug Monitor
# Detects simulator crashes, breakpoints, and provides diagnostics for Claude Code
# =============================================================================

set -euo pipefail

# Configuration
PROJECT_NAME="MiniCity"
BUNDLE_ID="com.drunkonjava.MiniCity"
MONITOR_DIR="/tmp/minicity_monitor"
CRASH_LOG_DIR="$HOME/Library/Logs/DiagnosticReports"
DEVICE_LOG_DIR="$HOME/Library/Logs/CoreSimulator"
OUTPUT_FILE="$MONITOR_DIR/current_status.json"
DEBUG_FIFO="$MONITOR_DIR/debug_events"
LLDB_SOCKET="/tmp/minicity_lldb.sock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create monitoring directory
mkdir -p "$MONITOR_DIR"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up monitor...${NC}"
    rm -f "$DEBUG_FIFO"
    rm -f "$LLDB_SOCKET"
    kill_background_processes
    exit 0
}

trap cleanup EXIT INT TERM

# Kill background processes
kill_background_processes() {
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Initialize monitoring infrastructure
initialize_monitor() {
    echo -e "${BLUE}Initializing MiniCity Monitor...${NC}"
    
    # Create FIFO for debug events if it doesn't exist
    if [[ ! -p "$DEBUG_FIFO" ]]; then
        mkfifo "$DEBUG_FIFO"
    fi
    
    # Initialize status file
    cat > "$OUTPUT_FILE" <<EOF
{
    "status": "initializing",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "pid": null,
    "simulator_state": "unknown",
    "last_crash": null,
    "last_breakpoint": null,
    "diagnostics": {}
}
EOF
}

# Get simulator device ID
get_simulator_device_id() {
    xcrun simctl list devices | grep "iPhone 16 Pro Max" | grep -E -o "\([A-F0-9\-]+\)" | tr -d '()' | head -1
}

# Check if app is running
is_app_running() {
    local device_id="$1"
    xcrun simctl spawn "$device_id" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID" && echo "true" || echo "false"
}

# Get app PID
get_app_pid() {
    local device_id="$1"
    xcrun simctl spawn "$device_id" launchctl list 2>/dev/null | grep "$BUNDLE_ID" | awk '{print $1}'
}

# Monitor system logs for crashes
monitor_crash_logs() {
    local device_id="$1"
    
    echo -e "${YELLOW}Starting crash log monitor...${NC}"
    
    # Monitor for crash reports
    fswatch -0 "$CRASH_LOG_DIR" | while read -d "" event; do
        if [[ "$event" == *"$PROJECT_NAME"* ]]; then
            echo -e "${RED}CRASH DETECTED: $event${NC}"
            parse_crash_log "$event"
        fi
    done &
    
    # Monitor simulator logs
    xcrun simctl spawn "$device_id" log stream \
        --predicate "processImagePath endswith \"$PROJECT_NAME\"" \
        --level debug 2>/dev/null | while read -r line; do
        
        # Check for crash indicators
        if echo "$line" | grep -qE "EXC_BAD_ACCESS|SIGABRT|SIGSEGV|SIGBUS|EXC_BREAKPOINT|crashed|assertion failed"; then
            echo -e "${RED}CRASH INDICATOR: $line${NC}"
            echo "crash:$line" > "$DEBUG_FIFO" &
        fi
        
        # Check for Metal errors
        if echo "$line" | grep -qE "MTLDebugRenderCommandEncoder|Metal API Validation|MTLCommandBuffer|fragment function|vertex function"; then
            echo -e "${YELLOW}METAL ERROR: $line${NC}"
            echo "metal_error:$line" > "$DEBUG_FIFO" &
        fi
        
        # Check for thread issues
        if echo "$line" | grep -qE "Thread.*crashed|Main Thread Checker|ThreadSanitizer"; then
            echo -e "${RED}THREAD ISSUE: $line${NC}"
            echo "thread_issue:$line" > "$DEBUG_FIFO" &
        fi
    done &
}

# Parse crash log and extract relevant information
parse_crash_log() {
    local crash_file="$1"
    
    if [[ ! -f "$crash_file" ]]; then
        return
    fi
    
    local crash_info=$(cat "$crash_file" | head -100)
    local crash_reason=$(echo "$crash_info" | grep -E "Exception Type:|Termination Reason:" | head -1)
    local crashed_thread=$(echo "$crash_info" | grep -E "Crashed Thread:" | head -1)
    local backtrace=$(echo "$crash_info" | sed -n '/Thread.*Crashed:/,/^$/p')
    
    # Create diagnostic JSON
    cat > "$MONITOR_DIR/last_crash.json" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "crash_file": "$crash_file",
    "reason": "$(echo "$crash_reason" | tr -d '"')",
    "thread": "$(echo "$crashed_thread" | tr -d '"')",
    "backtrace": $(echo "$backtrace" | jq -Rs .)
}
EOF
    
    # Update main status
    update_status "crashed" "$(cat "$MONITOR_DIR/last_crash.json")"
}

# Monitor LLDB for breakpoints
monitor_lldb() {
    local device_id="$1"
    
    echo -e "${YELLOW}Starting LLDB monitor...${NC}"
    
    # Create LLDB script for monitoring
    cat > "$MONITOR_DIR/lldb_monitor.py" <<'EOF'
import lldb
import json
import socket
import sys
import os

def breakpoint_callback(frame, bp_loc, dict):
    """Called when a breakpoint is hit"""
    thread = frame.GetThread()
    process = thread.GetProcess()
    
    # Collect diagnostic information
    diagnostic = {
        "event": "breakpoint",
        "timestamp": os.popen('date -u +"%Y-%m-%dT%H:%M:%SZ"').read().strip(),
        "thread_id": thread.GetThreadID(),
        "thread_name": thread.GetName() or "Unknown",
        "function": frame.GetFunctionName(),
        "file": str(frame.GetLineEntry().GetFileSpec()),
        "line": frame.GetLineEntry().GetLine(),
        "reason": thread.GetStopDescription(256),
        "backtrace": []
    }
    
    # Get backtrace
    for frame in thread:
        diagnostic["backtrace"].append({
            "index": frame.GetFrameID(),
            "function": frame.GetFunctionName(),
            "file": str(frame.GetLineEntry().GetFileSpec()),
            "line": frame.GetLineEntry().GetLine()
        })
    
    # Write to file
    with open("/tmp/minicity_monitor/breakpoint_hit.json", "w") as f:
        json.dump(diagnostic, f, indent=2)
    
    # Signal the monitor
    os.system('echo "breakpoint:hit" > /tmp/minicity_monitor/debug_events &')
    
    # Continue execution
    process.Continue()
    return False

# Set up monitoring
def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f lldb_monitor.monitor_app monitor_minicity')
    
def monitor_app(debugger, command, result, internal_dict):
    """Start monitoring the MiniCity app"""
    target = debugger.GetSelectedTarget()
    
    # Set breakpoint on common crash points
    crash_breakpoints = [
        "malloc_error_break",
        "__cxa_throw",
        "objc_exception_throw",
        "pthread_kill",
        "__assert_rtn"
    ]
    
    for bp_name in crash_breakpoints:
        bp = target.BreakpointCreateByName(bp_name)
        if bp.GetNumLocations() > 0:
            bp.SetScriptCallbackFunction("lldb_monitor.breakpoint_callback")
    
    print("MiniCity monitoring enabled")
EOF
    
    # Try to attach LLDB if app is running
    local pid=$(get_app_pid "$device_id")
    if [[ -n "$pid" ]] && [[ "$pid" != "0" ]]; then
        echo -e "${BLUE}Attempting to attach LLDB to PID: $pid${NC}"
        
        # Create LLDB commands file
        cat > "$MONITOR_DIR/lldb_commands.txt" <<EOF
process attach --pid $pid
command script import $MONITOR_DIR/lldb_monitor.py
monitor_minicity
continue
EOF
        
        # Run LLDB in background
        lldb -s "$MONITOR_DIR/lldb_commands.txt" 2>&1 | while read -r line; do
            if echo "$line" | grep -qE "stopped|breakpoint|crashed|EXC_"; then
                echo -e "${RED}LLDB: $line${NC}"
                echo "lldb:$line" > "$DEBUG_FIFO" &
            fi
        done &
    fi
}

# Collect Metal diagnostics
collect_metal_diagnostics() {
    local device_id="$1"
    
    echo -e "${BLUE}Collecting Metal diagnostics...${NC}"
    
    # Set Metal debug environment variables
    export MTL_DEBUG_LAYER=1
    export MTL_SHADER_VALIDATION=1
    export MTL_CAPTURE_ENABLED=1
    
    # Try to capture GPU frame
    xcrun simctl spawn "$device_id" MTLCaptureManager 2>/dev/null || true
    
    # Get Metal device info
    local metal_info=$(xcrun simctl spawn "$device_id" metal-cli device 2>/dev/null || echo "{}")
    
    cat > "$MONITOR_DIR/metal_diagnostics.json" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "debug_layer": true,
    "shader_validation": true,
    "device_info": $metal_info
}
EOF
}

# Monitor process state
monitor_process_state() {
    local device_id="$1"
    
    while true; do
        local is_running=$(is_app_running "$device_id")
        local pid=$(get_app_pid "$device_id" 2>/dev/null || echo "0")
        
        if [[ "$is_running" == "true" ]]; then
            # Get process info
            local proc_info=$(xcrun simctl spawn "$device_id" ps aux 2>/dev/null | grep "$PROJECT_NAME" | grep -v grep || true)
            
            # Get memory usage
            local memory_usage=$(echo "$proc_info" | awk '{print $4}' || echo "0")
            
            # Get CPU usage
            local cpu_usage=$(echo "$proc_info" | awk '{print $3}' || echo "0")
            
            # Update status
            cat > "$OUTPUT_FILE" <<EOF
{
    "status": "running",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "pid": $pid,
    "simulator_state": "active",
    "memory_usage": "$memory_usage%",
    "cpu_usage": "$cpu_usage%",
    "last_crash": $(cat "$MONITOR_DIR/last_crash.json" 2>/dev/null || echo null),
    "last_breakpoint": $(cat "$MONITOR_DIR/breakpoint_hit.json" 2>/dev/null || echo null),
    "metal_diagnostics": $(cat "$MONITOR_DIR/metal_diagnostics.json" 2>/dev/null || echo {})
}
EOF
        else
            # Check if it crashed
            local latest_crash=$(ls -t "$CRASH_LOG_DIR"/*"$PROJECT_NAME"* 2>/dev/null | head -1)
            if [[ -n "$latest_crash" ]]; then
                parse_crash_log "$latest_crash"
            fi
            
            cat > "$OUTPUT_FILE" <<EOF
{
    "status": "not_running",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "pid": null,
    "simulator_state": "inactive",
    "last_crash": $(cat "$MONITOR_DIR/last_crash.json" 2>/dev/null || echo null),
    "last_breakpoint": $(cat "$MONITOR_DIR/breakpoint_hit.json" 2>/dev/null || echo null),
    "diagnostics": {}
}
EOF
        fi
        
        sleep 1
    done &
}

# Process debug events
process_debug_events() {
    echo -e "${BLUE}Processing debug events...${NC}"
    
    while true; do
        if read -r event < "$DEBUG_FIFO"; then
            local event_type="${event%%:*}"
            local event_data="${event#*:}"
            
            echo -e "${YELLOW}Debug Event: $event_type${NC}"
            
            case "$event_type" in
                "crash")
                    echo -e "${RED}Processing crash event${NC}"
                    collect_crash_diagnostics
                    ;;
                "breakpoint")
                    echo -e "${YELLOW}Processing breakpoint event${NC}"
                    collect_breakpoint_diagnostics
                    ;;
                "metal_error")
                    echo -e "${YELLOW}Processing Metal error${NC}"
                    collect_metal_diagnostics "$(get_simulator_device_id)"
                    ;;
                "thread_issue")
                    echo -e "${RED}Processing thread issue${NC}"
                    collect_thread_diagnostics
                    ;;
            esac
            
            # Notify Claude Code
            notify_claude_code "$event_type" "$event_data"
        fi
    done &
}

# Collect comprehensive crash diagnostics
collect_crash_diagnostics() {
    local device_id=$(get_simulator_device_id)
    
    echo -e "${RED}Collecting crash diagnostics...${NC}"
    
    # Get the latest crash report
    local latest_crash=$(ls -t "$CRASH_LOG_DIR"/*"$PROJECT_NAME"* 2>/dev/null | head -1)
    
    # Collect system logs
    local system_logs=$(xcrun simctl spawn "$device_id" log show --last 1m --predicate "processImagePath endswith \"$PROJECT_NAME\"" 2>/dev/null | tail -100)
    
    # Create comprehensive diagnostic
    cat > "$MONITOR_DIR/crash_diagnostic.json" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "type": "crash",
    "crash_report": "$(echo "$latest_crash" | xargs basename 2>/dev/null)",
    "system_logs": $(echo "$system_logs" | jq -Rs .),
    "suggested_actions": [
        "Check Metal shader compilation",
        "Verify depth buffer configuration",
        "Review memory management in render loop",
        "Check thread safety of shared resources",
        "Validate vertex buffer bindings"
    ]
}
EOF
}

# Notify Claude Code about events
notify_claude_code() {
    local event_type="$1"
    local event_data="$2"
    
    # Create notification file for Claude Code
    cat > "$MONITOR_DIR/claude_notification.json" <<EOF
{
    "event": "$event_type",
    "data": "$event_data",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status_file": "$OUTPUT_FILE",
    "action_required": true,
    "diagnostic_files": [
        "$MONITOR_DIR/crash_diagnostic.json",
        "$MONITOR_DIR/metal_diagnostics.json",
        "$MONITOR_DIR/breakpoint_hit.json"
    ]
}
EOF
    
    # Print to stdout for Claude Code to capture
    echo "CLAUDE_CODE_NOTIFICATION: $(cat "$MONITOR_DIR/claude_notification.json" | jq -c .)"
}

# Main monitoring loop
main() {
    initialize_monitor
    
    local device_id=$(get_simulator_device_id)
    
    if [[ -z "$device_id" ]]; then
        echo -e "${RED}Error: No simulator device found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Monitoring device: $device_id${NC}"
    
    # Start all monitoring components
    monitor_crash_logs "$device_id"
    monitor_lldb "$device_id"
    monitor_process_state "$device_id"
    process_debug_events
    collect_metal_diagnostics "$device_id"
    
    echo -e "${GREEN}MiniCity Monitor is running${NC}"
    echo -e "${YELLOW}Status file: $OUTPUT_FILE${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
    
    # Keep the script running
    while true; do
        sleep 10
        
        # Print status update
        if [[ -f "$OUTPUT_FILE" ]]; then
            local status=$(jq -r '.status' "$OUTPUT_FILE" 2>/dev/null)
            echo -e "${BLUE}[$(date '+%H:%M:%S')] Status: $status${NC}"
        fi
    done
}

# Run main function
main "$@"
