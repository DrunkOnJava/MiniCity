#!/bin/bash

# Claude Code CLI Integration Helper
# This script should be called by Claude Code instead of 'make run'
# =================================================================

set -euo pipefail

PROJECT_DIR="/Users/griffin/Projects/MiniCity/MiniCity"
cd "$PROJECT_DIR"

# Function to output structured data for Claude Code
output_for_claude() {
    local event="$1"
    local data="$2"
    echo "CLAUDE_CODE_EVENT:$event"
    echo "CLAUDE_CODE_DATA:$data"
}

# Main execution
echo "Starting MiniCity with Claude Code monitoring..."

# Clean previous session
make claude-clean 2>/dev/null || true

# Run with monitoring and capture output
make claude-run 2>&1 | while IFS= read -r line; do
    # Forward all output
    echo "$line"
    
    # Detect and parse Claude Code events
    if [[ "$line" == CLAUDE_CODE_* ]]; then
        event_type=$(echo "$line" | cut -d: -f1)
        event_data=$(echo "$line" | cut -d: -f2-)
        
        case "$event_type" in
            "CLAUDE_CODE_CRASH")
                # App crashed - provide diagnostic
                echo "=== CRASH DETECTED ==="
                make claude-diagnose 2>/dev/null | jq '.'
                echo "=== END DIAGNOSTIC ==="
                ;;
                
            "CLAUDE_CODE_BUILD_FAILED")
                # Build failed - show errors
                echo "=== BUILD FAILED ==="
                echo "$event_data" | jq -r '.errors[]' 2>/dev/null || echo "$event_data"
                echo "=== END BUILD ERRORS ==="
                exit 1
                ;;
                
            "CLAUDE_CODE_SUCCESS")
                # App is stable
                echo "=== APP RUNNING SUCCESSFULLY ==="
                ;;
                
            "CLAUDE_CODE_ACTION_REQUIRED")
                # Manual intervention needed
                echo "=== ACTION REQUIRED ==="
                echo "$event_data" | jq '.' 2>/dev/null || echo "$event_data"
                echo "=== END ACTION ==="
                ;;
        esac
    fi
    
    # Exit conditions
    if [[ "$line" == *"CLAUDE_CODE_COMPLETE"* ]]; then
        break
    fi
done

# Final status check
echo "=== FINAL STATUS ==="
make claude-status 2>/dev/null | jq '.'
echo "=== END STATUS ==="

# Exit code based on final status
status=$(make claude-status 2>/dev/null | jq -r '.status' || echo "unknown")
if [[ "$status" == "running" ]]; then
    echo "MiniCity is running successfully"
    exit 0
else
    echo "MiniCity ended with status: $status"
    exit 1
fi
