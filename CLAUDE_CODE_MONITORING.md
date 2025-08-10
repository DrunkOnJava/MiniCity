# Claude Code Crash Detection & Diagnostic System

## Overview

This system enables Claude Code CLI to automatically detect, diagnose, and potentially fix iOS simulator crashes and debug breakpoints that occur during development of the MiniCity project. It provides real-time monitoring and structured diagnostics that Claude Code can understand and act upon.

## Features

- **Automatic Crash Detection**: Monitors for app crashes, Metal errors, thread issues, and breakpoints
- **Comprehensive Diagnostics**: Collects crash logs, system logs, Metal diagnostics, and stack traces
- **Structured Output**: Provides JSON-formatted diagnostics that Claude Code can parse
- **Automated Recovery**: Attempts to restart the app after crashes (up to 3 times)
- **Fix Suggestions**: Generates specific code fixes based on crash analysis
- **Real-time Monitoring**: Continuously tracks app status and performance

## Quick Start

### For Claude Code CLI

Instead of using `make run`, use:

```bash
make claude-run
```

This will:
1. Start the crash monitoring system
2. Build and run the app
3. Detect any crashes or breakpoints
4. Provide structured diagnostics
5. Attempt auto-recovery if possible

## Available Commands

### Primary Commands

```bash
# Run with intelligent monitoring (recommended for Claude Code)
make claude-run

# Get current diagnostics
make claude-diagnose

# Check app status
make claude-status

# View suggested fixes
make claude-fix

# Clean monitoring data
make claude-clean
```

### Advanced Commands

```bash
# Start monitor daemon only
make claude-monitor

# Interactive diagnostic mode
./scripts/monitoring/claude_diagnostic.sh interactive

# Continuous monitoring mode
./scripts/monitoring/claude_diagnostic.sh monitor
```

## Output Format

The system provides structured JSON output that Claude Code can parse:

```json
{
  "event": "crash_detected",
  "timestamp": "2025-01-30T12:00:00Z",
  "crash_analysis": {
    "crash_type": "Metal Shader Error",
    "likely_causes": [...],
    "suggested_fixes": [...]
  },
  "automated_fixes": [...],
  "diagnostic_files": [...]
}
```

## Understanding Diagnostics

### Status Types

- `running`: App is running normally
- `crashed`: App has crashed (check crash_analysis)
- `not_running`: App is not running (may be normal or crashed)
- `initializing`: Monitor is starting up

### Event Types

Claude Code will see these event markers in the output:

- `CLAUDE_CODE_BUILD_FAILED`: Build compilation failed
- `CLAUDE_CODE_CRASH`: App crashed during runtime
- `CLAUDE_CODE_SUCCESS`: App is running stably
- `CLAUDE_CODE_ACTION_REQUIRED`: Manual intervention needed
- `CLAUDE_CODE_COMPLETE`: Run session finished

### Crash Types

The system identifies and provides specific fixes for:

1. **Memory Access Violations** (EXC_BAD_ACCESS)
   - Null pointer dereferences
   - Buffer overflows
   - Deallocated memory access

2. **Metal Shader Errors**
   - Shader compilation failures
   - Missing texture bindings
   - Vertex descriptor mismatches

3. **Threading Issues**
   - Race conditions
   - Deadlocks
   - Main thread blocking

## Automated Fixes

The system suggests specific code changes:

```json
{
  "type": "shader_validation",
  "file": "MetalEngine.swift",
  "line_range": [200, 250],
  "fix": "Add shader validation: guard let library = device.makeDefaultLibrary() else { ... }"
}
```

## Integration with Claude Code

### Reading Diagnostics

```bash
# Get diagnostics as JSON
DIAGNOSTIC=$(make claude-diagnose 2>/dev/null)

# Parse specific fields
CRASH_TYPE=$(echo "$DIAGNOSTIC" | jq -r '.crash_analysis.crash_type')
FIXES=$(echo "$DIAGNOSTIC" | jq -r '.automated_fixes[]')
```

### Monitoring Loop

```bash
# Start monitoring and capture events
make claude-run | while read line; do
    if [[ "$line" == CLAUDE_CODE_* ]]; then
        EVENT=$(echo "$line" | cut -d: -f1)
        DATA=$(echo "$line" | cut -d: -f2-)
        
        case "$EVENT" in
            "CLAUDE_CODE_CRASH")
                # Handle crash
                echo "$DATA" | jq '.crash_analysis'
                ;;
            "CLAUDE_CODE_SUCCESS")
                # App is stable
                break
                ;;
        esac
    fi
done
```

## File Locations

### Monitoring Files
- Status: `/tmp/minicity_monitor/current_status.json`
- Last Crash: `/tmp/minicity_monitor/last_crash.json`
- Metal Diagnostics: `/tmp/minicity_monitor/metal_diagnostics.json`
- Claude Notifications: `/tmp/minicity_monitor/claude_notification.json`

### Build Logs
- Build Output: `build/last_build.log`
- Diagnostics: `build/last_diagnostic.json`

### System Logs
- Crash Reports: `~/Library/Logs/DiagnosticReports/*MiniCity*`
- Simulator Logs: `~/Library/Logs/CoreSimulator/`

## Troubleshooting

### Monitor Not Starting

```bash
# Check if monitor is running
ps aux | grep crash_monitor

# View monitor logs
tail -f /tmp/minicity_monitor/monitor.log
```

### No Diagnostics Available

```bash
# Ensure simulator is running
xcrun simctl list devices | grep Booted

# Check app status
xcrun simctl spawn booted launchctl list | grep MiniCity
```

### False Positives

If the system reports crashes when the app is running fine:

```bash
# Clean monitoring data
make claude-clean

# Restart monitoring
make claude-monitor
```

## Best Practices for Claude Code

1. **Always use `make claude-run`** instead of `make run` for automatic crash detection

2. **Check diagnostics after failures**:
   ```bash
   make claude-diagnose | jq '.crash_analysis'
   ```

3. **Parse structured output** using the CLAUDE_CODE_* markers

4. **Clean between sessions** to avoid stale data:
   ```bash
   make claude-clean
   ```

5. **Use automated fixes** as starting points, not definitive solutions

## Example Workflow

```bash
# 1. Clean previous session
make claude-clean

# 2. Run with monitoring
make claude-run

# 3. If crash occurs, get diagnostics
make claude-diagnose > crash_report.json

# 4. View suggested fixes
cat crash_report.json | jq '.automated_fixes'

# 5. Apply fixes and retry
# ... edit code based on suggestions ...
make claude-run
```

## Advanced Features

### Custom Diagnostics

Add custom diagnostic collectors in `scripts/monitoring/claude_diagnostic.sh`:

```bash
collect_custom_diagnostics() {
    # Your custom logic here
    echo '{"custom_data": "value"}'
}
```

### Extended Monitoring

Modify monitoring sensitivity in `scripts/monitoring/crash_monitor.sh`:

```bash
# Add more crash indicators
if echo "$line" | grep -qE "YOUR_PATTERN"; then
    echo "custom_event:$line" > "$DEBUG_FIFO" &
fi
```

## Support

For issues or improvements:
1. Check monitor logs: `/tmp/minicity_monitor/monitor.log`
2. Review diagnostics: `make claude-diagnose`
3. Clean and restart: `make claude-clean && make claude-run`

---

**Note**: This system is specifically designed for Claude Code CLI integration. For regular development, use the standard `make run` command.
