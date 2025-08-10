#!/bin/bash

# Claude Code Diagnostic Interface
# Provides structured diagnostics for automated troubleshooting
# =============================================================================

set -euo pipefail

# Configuration
PROJECT_DIR="/Users/griffin/Projects/MiniCity/MiniCity"
MONITOR_DIR="/tmp/minicity_monitor"
DIAGNOSTIC_OUTPUT="/tmp/minicity_claude_diagnostic.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get current app status
get_app_status() {
    if [[ -f "$MONITOR_DIR/current_status.json" ]]; then
        cat "$MONITOR_DIR/current_status.json"
    else
        echo '{"status": "unknown", "error": "Monitor not running"}'
    fi
}

# Analyze crash and provide fix suggestions
analyze_crash() {
    local crash_file="$1"
    
    if [[ ! -f "$crash_file" ]]; then
        echo '{"error": "Crash file not found"}'
        return
    fi
    
    local crash_content=$(cat "$crash_file")
    local analysis='{}'
    
    # Analyze crash type
    if echo "$crash_content" | grep -q "EXC_BAD_ACCESS"; then
        analysis=$(cat <<EOF
{
    "crash_type": "Memory Access Violation",
    "likely_causes": [
        "Null pointer dereference",
        "Accessing deallocated memory",
        "Buffer overflow",
        "Incorrect pointer arithmetic"
    ],
    "suggested_fixes": [
        {
            "file": "MetalEngine.swift",
            "action": "Add null checks before accessing Metal buffers",
            "code": "guard let buffer = renderPassDescriptor.colorAttachments[0].texture else { return }"
        },
        {
            "file": "MetalEngine.swift",
            "action": "Ensure proper buffer allocation",
            "code": "let bufferSize = MemoryLayout<Float>.stride * vertexCount\nguard bufferSize > 0 else { return }"
        }
    ]
}
EOF
        )
    elif echo "$crash_content" | grep -q "fragment function"; then
        analysis=$(cat <<EOF
{
    "crash_type": "Metal Shader Error",
    "likely_causes": [
        "Invalid shader compilation",
        "Missing texture binding",
        "Incorrect vertex descriptor",
        "Buffer size mismatch"
    ],
    "suggested_fixes": [
        {
            "file": "Shaders.metal",
            "action": "Verify texture sampling coordinates",
            "code": "float2 texCoord = clamp(in.texCoords, 0.0, 1.0);"
        },
        {
            "file": "MetalEngine.swift",
            "action": "Check texture creation",
            "code": "textureDescriptor.usage = [.shaderRead, .renderTarget]"
        }
    ]
}
EOF
        )
    elif echo "$crash_content" | grep -q "Thread.*crashed"; then
        analysis=$(cat <<EOF
{
    "crash_type": "Threading Issue",
    "likely_causes": [
        "Race condition",
        "Deadlock",
        "Unsafe concurrent access",
        "Main thread blocking"
    ],
    "suggested_fixes": [
        {
            "file": "MetalEngine.swift",
            "action": "Use dispatch queues for thread safety",
            "code": "DispatchQueue.main.async { [weak self] in\n    self?.updateUI()\n}"
        },
        {
            "file": "TrafficSimulation.swift",
            "action": "Add thread synchronization",
            "code": "private let updateQueue = DispatchQueue(label: \"traffic.update\", attributes: .concurrent)"
        }
    ]
}
EOF
        )
    fi
    
    echo "$analysis"
}

# Analyze Metal validation errors
analyze_metal_errors() {
    local log_file="$1"
    local errors=()
    
    if grep -q "MTLDebugRenderCommandEncoder" "$log_file" 2>/dev/null; then
        errors+=("Render command encoder validation failed")
    fi
    
    if grep -q "Resource Storage Mode" "$log_file" 2>/dev/null; then
        errors+=("Incorrect Metal resource storage mode")
    fi
    
    if grep -q "Texture usage" "$log_file" 2>/dev/null; then
        errors+=("Invalid texture usage flags")
    fi
    
    # Generate fixes based on errors
    local fixes='[]'
    if [[ ${#errors[@]} -gt 0 ]]; then
        fixes=$(cat <<EOF
[
    {
        "error": "$(printf '%s\n' "${errors[@]}" | jq -Rs .)",
        "fix": {
            "file": "MetalEngine.swift",
            "function": "setupMetal()",
            "changes": [
                "Set proper storage mode: .storageModeShared for simulator",
                "Add validation layer: metalDevice.makeCommandQueue()",
                "Enable GPU frame capture: captureManager.startCapture()"
            ]
        }
    }
]
EOF
        )
    fi
    
    echo "$fixes"
}

# Get comprehensive diagnostics
get_comprehensive_diagnostics() {
    echo -e "${BLUE}Collecting comprehensive diagnostics...${NC}"
    
    # Get current status
    local status=$(get_app_status)
    
    # Get latest crash if any
    local latest_crash=""
    if ls "$HOME/Library/Logs/DiagnosticReports/"*MiniCity* 2>/dev/null | head -1 > /dev/null; then
        latest_crash=$(ls -t "$HOME/Library/Logs/DiagnosticReports/"*MiniCity* 2>/dev/null | head -1)
    fi
    
    # Get simulator logs
    local device_id=$(xcrun simctl list devices | grep "iPhone 16 Pro Max" | grep -E -o "\([A-F0-9\-]+\)" | tr -d '()' | head -1)
    local recent_logs=""
    if [[ -n "$device_id" ]]; then
        recent_logs=$(xcrun simctl spawn "$device_id" log show --last 30s --predicate 'processImagePath endswith "MiniCity"' 2>/dev/null | tail -50 || echo "")
    fi
    
    # Analyze crash if present
    local crash_analysis='{}'
    if [[ -n "$latest_crash" ]]; then
        crash_analysis=$(analyze_crash "$latest_crash")
    fi
    
    # Check for Metal errors
    local metal_errors='[]'
    if [[ -n "$recent_logs" ]]; then
        metal_errors=$(echo "$recent_logs" | analyze_metal_errors /dev/stdin)
    fi
    
    # Get build errors if any
    local build_errors='[]'
    if [[ -f "$PROJECT_DIR/build/last_build.log" ]]; then
        build_errors=$(grep -E "error:|warning:" "$PROJECT_DIR/build/last_build.log" 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0))' || echo '[]')
    fi
    
    # Generate comprehensive diagnostic
    cat > "$DIAGNOSTIC_OUTPUT" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "app_status": $status,
    "crash_analysis": $crash_analysis,
    "metal_errors": $metal_errors,
    "build_errors": $build_errors,
    "recent_logs": $(echo "$recent_logs" | jq -Rs . 2>/dev/null || echo '""'),
    "recommended_actions": $(generate_recommended_actions "$status" "$crash_analysis"),
    "automated_fixes": $(generate_automated_fixes "$crash_analysis" "$metal_errors")
}
EOF
    
    echo -e "${GREEN}Diagnostics saved to: $DIAGNOSTIC_OUTPUT${NC}"
    cat "$DIAGNOSTIC_OUTPUT"
}

# Generate recommended actions based on diagnostics
generate_recommended_actions() {
    local status="$1"
    local crash_analysis="$2"
    
    local actions='[]'
    
    # Check status
    local app_status=$(echo "$status" | jq -r '.status' 2>/dev/null || echo "unknown")
    
    if [[ "$app_status" == "crashed" ]] || [[ "$app_status" == "not_running" ]]; then
        actions=$(cat <<EOF
[
    "Check Metal shader compilation",
    "Verify simulator Metal support",
    "Review recent code changes in MetalEngine.swift",
    "Validate vertex and fragment shaders",
    "Check memory management in render loop",
    "Ensure proper resource cleanup"
]
EOF
        )
    elif [[ "$app_status" == "running" ]]; then
        actions='["Monitor performance metrics", "Check for memory leaks", "Validate render pipeline"]'
    fi
    
    echo "$actions"
}

# Generate automated fixes
generate_automated_fixes() {
    local crash_analysis="$1"
    local metal_errors="$2"
    
    cat <<EOF
[
    {
        "type": "shader_validation",
        "file": "MetalEngine.swift",
        "line_range": [200, 250],
        "fix": "Add shader validation: guard let library = device.makeDefaultLibrary() else { fatalError(\"Failed to create Metal library\") }"
    },
    {
        "type": "buffer_allocation",
        "file": "MetalEngine.swift",
        "line_range": [300, 350],
        "fix": "Ensure buffer size: let bufferSize = max(1, vertices.count * MemoryLayout<Vertex>.stride)"
    },
    {
        "type": "depth_configuration",
        "file": "MetalEngine.swift",
        "line_range": [400, 450],
        "fix": "Configure depth state: depthStencilDescriptor.depthCompareFunction = .less"
    }
]
EOF
}

# Monitor and report mode
monitor_mode() {
    echo -e "${GREEN}Starting diagnostic monitor for Claude Code...${NC}"
    
    while true; do
        get_comprehensive_diagnostics > /dev/null 2>&1
        
        # Check for issues
        local status=$(jq -r '.app_status.status' "$DIAGNOSTIC_OUTPUT" 2>/dev/null)
        
        if [[ "$status" == "crashed" ]] || [[ "$status" == "not_running" ]]; then
            echo -e "${RED}ISSUE DETECTED - Status: $status${NC}"
            echo "CLAUDE_CODE_ACTION_REQUIRED: $(cat "$DIAGNOSTIC_OUTPUT" | jq -c .)"
        fi
        
        sleep 5
    done
}

# Interactive diagnostic mode
interactive_mode() {
    while true; do
        echo -e "\n${BLUE}MiniCity Diagnostic Menu${NC}"
        echo "1. Get current status"
        echo "2. Analyze latest crash"
        echo "3. Check Metal errors"
        echo "4. Get comprehensive diagnostics"
        echo "5. Start continuous monitoring"
        echo "6. Generate fix suggestions"
        echo "7. Exit"
        
        read -p "Select option: " choice
        
        case $choice in
            1) get_app_status | jq . ;;
            2) 
                latest_crash=$(ls -t "$HOME/Library/Logs/DiagnosticReports/"*MiniCity* 2>/dev/null | head -1)
                if [[ -n "$latest_crash" ]]; then
                    analyze_crash "$latest_crash" | jq .
                else
                    echo "No crash logs found"
                fi
                ;;
            3) 
                device_id=$(xcrun simctl list devices | grep "iPhone 16 Pro Max" | grep -E -o "\([A-F0-9\-]+\)" | tr -d '()' | head -1)
                xcrun simctl spawn "$device_id" log show --last 1m --predicate 'processImagePath endswith "MiniCity"' 2>/dev/null | analyze_metal_errors /dev/stdin | jq .
                ;;
            4) get_comprehensive_diagnostics ;;
            5) monitor_mode ;;
            6) generate_automated_fixes "{}" "[]" | jq . ;;
            7) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Main execution
case "${1:-}" in
    "status")
        get_app_status | jq .
        ;;
    "diagnose")
        get_comprehensive_diagnostics
        ;;
    "monitor")
        monitor_mode
        ;;
    "interactive")
        interactive_mode
        ;;
    *)
        # Default: provide diagnostics for Claude Code
        get_comprehensive_diagnostics
        ;;
esac
