# Automatic Crash Detection & Diagnostics

## Overview

The MiniCity project now has **automatic crash detection and diagnostics** built directly into the standard `make` commands. This means Claude Code can use the normal commands and still get intelligent crash handling.

## How It Works

### Standard Commands (Now Enhanced)

```bash
make build  # Builds with automatic error diagnostics
make run    # Runs with crash monitoring and auto-recovery
```

These commands now automatically:
- ✅ Detect build failures and provide structured error messages
- ✅ Monitor for app crashes during runtime
- ✅ Attempt automatic recovery (up to 3 times)
- ✅ Provide detailed diagnostics for debugging
- ✅ Output structured data that Claude Code can parse

### What Claude Code Will See

When using `make run`, Claude Code will see special markers in stderr:

```
CLAUDE_CODE_BUILD_SUCCESS: Build completed successfully
CLAUDE_CODE_BUILD_FAILED: {"event": "build_failed", "errors": [...]}
CLAUDE_CODE_CRASH: {"crash_type": "Metal Shader Error", ...}
CLAUDE_CODE_SUCCESS: App running successfully
```

### Automatic Features

1. **Build Diagnostics**: If build fails, automatically generates error report
2. **Crash Detection**: Monitors app for 30 seconds after launch
3. **Auto-Recovery**: Attempts to restart app after crashes
4. **Diagnostic Reports**: Provides crash analysis with suggested fixes
5. **Clean Monitoring**: Automatically cleans up monitoring processes

### Disabling Monitoring

If you need to run without monitoring (for performance testing, etc.):

```bash
ENABLE_MONITORING=0 make run
```

### Additional Commands

For manual diagnostics:

```bash
make diagnose    # Get current app diagnostics
make status      # Check current app status
make monitor-logs # View monitoring logs
```

### How Crashes Are Handled

When a crash is detected:

1. **Immediate Detection**: Monitor catches the crash signal
2. **Diagnostic Collection**: Gathers crash logs, stack traces, Metal errors
3. **Analysis**: Identifies crash type (memory, shader, threading)
4. **Recovery Attempt**: Tries to restart the app
5. **Report Generation**: Provides structured diagnostic data

### Example Output

#### Successful Run
```
Building MiniCity with monitoring...
✓ Build successful
Launching app with monitoring...
✓ App launched
Monitoring for crashes (30 seconds)...
.....
✓ App is stable and running
```

#### Crash Detected
```
Building MiniCity with monitoring...
✓ Build successful
Launching app with monitoring...
✓ App launched
Monitoring for crashes (30 seconds)...
...
CRASH DETECTED (#1)
{
  "crash_type": "Metal Shader Error",
  "likely_causes": ["Invalid shader compilation", "Missing texture binding"],
  "suggested_fixes": [...]
}
Attempting recovery...
```

### Benefits for Claude Code

1. **No Learning Curve**: Uses standard `make run` command
2. **Automatic Detection**: No need to check if app actually launched
3. **Structured Data**: JSON diagnostics for easy parsing
4. **Self-Healing**: Attempts recovery without intervention
5. **Detailed Diagnostics**: Specific error types and fixes

### Files Created

The monitoring system creates these temporary files:

- `/tmp/minicity_monitor/current_status.json` - Current app status
- `build/last_build.log` - Last build output
- `build/last_diagnostic.json` - Last diagnostic report

These are automatically cleaned with `make clean`.

## Implementation Details

The monitoring is implemented through:

1. **Makefile Integration**: Enhanced `build` and `run` targets
2. **Background Monitor**: Watches for crashes and errors
3. **Diagnostic Engine**: Analyzes and categorizes issues
4. **Recovery System**: Attempts automatic fixes

## For Developers

### Testing the System

```bash
# Test monitoring is working
make run

# Check status while running
make status

# View diagnostics after a crash
make diagnose
```

### Debugging the Monitor

```bash
# View monitor logs
make monitor-logs

# Run without monitoring
ENABLE_MONITORING=0 make run

# Clean monitoring data
make clean
```

## Summary

The crash detection system is now **fully integrated** into the standard build system. Claude Code can continue using `make run` and `make build` as normal, but will now automatically get:

- Build error diagnostics
- Crash detection
- Auto-recovery
- Detailed debugging information

No special commands or knowledge required - it just works! 🎉
