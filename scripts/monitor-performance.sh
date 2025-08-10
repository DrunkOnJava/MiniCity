#!/bin/bash
# Monitor MiniCity performance metrics

set -e

PROJECT_NAME="MiniCity"
BUNDLE_ID="com.drunkonjava.MiniCity"
OUTPUT_DIR="metrics"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== MiniCity Performance Monitor ===${NC}\n"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get the booted simulator
BOOTED_DEVICE=$(xcrun simctl list devices | grep "(Booted)" | head -1 | cut -d" " -f7- | sed 's/ (Booted)//')

if [ -z "$BOOTED_DEVICE" ]; then
    echo -e "${RED}No simulator running. Please start a simulator first.${NC}"
    exit 1
fi

echo -e "${GREEN}Monitoring: ${BOOTED_DEVICE}${NC}\n"

# Function to get app PID
get_app_pid() {
    xcrun simctl spawn booted launchctl list | grep "$BUNDLE_ID" | awk '{print $1}'
}

# Function to monitor CPU
monitor_cpu() {
    echo -e "${YELLOW}CPU Usage:${NC}"
    PID=$(get_app_pid)
    if [ ! -z "$PID" ]; then
        top -pid $PID -l 1 | tail -1 | awk '{printf "  Process: %.1f%%\n", $3}'
    else
        echo "  App not running"
    fi
}

# Function to monitor memory
monitor_memory() {
    echo -e "${YELLOW}Memory Usage:${NC}"
    PID=$(get_app_pid)
    if [ ! -z "$PID" ]; then
        # Get memory info from simulator
        MEMORY=$(xcrun simctl spawn booted vmmap $PID 2>/dev/null | grep "TOTAL" | tail -1 | awk '{print $3}')
        if [ ! -z "$MEMORY" ]; then
            echo "  Total: $MEMORY"
        fi
    else
        echo "  App not running"
    fi
}

# Function to monitor GPU (Metal)
monitor_gpu() {
    echo -e "${YELLOW}GPU Performance:${NC}"
    # Check for Metal performance hints
    METAL_LOG=$(xcrun simctl spawn booted log show --predicate "processImagePath endswith '$PROJECT_NAME'" --last 1m 2>/dev/null | grep -i "metal" | head -5)
    if [ ! -z "$METAL_LOG" ]; then
        echo "$METAL_LOG" | while read line; do
            echo "  $line" | cut -c1-80
        done
    else
        echo "  No recent Metal activity"
    fi
}

# Function to monitor FPS
monitor_fps() {
    echo -e "${YELLOW}Frame Rate:${NC}"
    # Look for CADisplayLink or frame timing logs
    FPS_LOG=$(xcrun simctl spawn booted log show --predicate "processImagePath endswith '$PROJECT_NAME'" --last 10s 2>/dev/null | grep -E "(FPS|frame|display)" | tail -1)
    if [ ! -z "$FPS_LOG" ]; then
        echo "  $FPS_LOG" | cut -c1-80
    else
        echo "  No FPS data available"
    fi
}

# Function to monitor network
monitor_network() {
    echo -e "${YELLOW}Network Activity:${NC}"
    NETWORK_LOG=$(xcrun simctl spawn booted log show --predicate "processImagePath endswith '$PROJECT_NAME'" --last 30s 2>/dev/null | grep -E "(network|http|url)" -i | wc -l)
    echo "  Requests in last 30s: $NETWORK_LOG"
}

# Function to check for errors
check_errors() {
    echo -e "${YELLOW}Recent Errors:${NC}"
    ERROR_COUNT=$(xcrun simctl spawn booted log show --predicate "processImagePath endswith '$PROJECT_NAME' AND messageType == 16" --last 1m 2>/dev/null | wc -l)
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "  ${RED}$ERROR_COUNT errors in last minute${NC}"
        xcrun simctl spawn booted log show --predicate "processImagePath endswith '$PROJECT_NAME' AND messageType == 16" --last 1m 2>/dev/null | tail -3 | while read line; do
            echo "  $line" | cut -c1-80
        done
    else
        echo -e "  ${GREEN}No recent errors${NC}"
    fi
}

# Function to save metrics
save_metrics() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTPUT_FILE="$OUTPUT_DIR/performance_$TIMESTAMP.txt"
    
    {
        echo "MiniCity Performance Report"
        echo "============================"
        echo "Date: $(date)"
        echo "Device: $BOOTED_DEVICE"
        echo ""
        
        echo "CPU & Memory:"
        monitor_cpu
        monitor_memory
        echo ""
        
        echo "Graphics:"
        monitor_gpu
        monitor_fps
        echo ""
        
        echo "Network:"
        monitor_network
        echo ""
        
        echo "Errors:"
        check_errors
    } > "$OUTPUT_FILE"
    
    echo -e "\n${GREEN}Report saved to: $OUTPUT_FILE${NC}"
}

# Main monitoring loop
if [ "$1" == "--continuous" ]; then
    echo "Starting continuous monitoring (Press Ctrl+C to stop)..."
    while true; do
        clear
        echo -e "${CYAN}=== MiniCity Performance Monitor ===${NC}"
        echo -e "${CYAN}$(date)${NC}\n"
        
        monitor_cpu
        echo ""
        monitor_memory
        echo ""
        monitor_gpu
        echo ""
        monitor_fps
        echo ""
        monitor_network
        echo ""
        check_errors
        
        sleep 5
    done
else
    # Single run
    monitor_cpu
    echo ""
    monitor_memory
    echo ""
    monitor_gpu
    echo ""
    monitor_fps
    echo ""
    monitor_network
    echo ""
    check_errors
    
    if [ "$1" == "--save" ]; then
        save_metrics
    fi
fi