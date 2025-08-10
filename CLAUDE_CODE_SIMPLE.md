# IMPORTANT: Crash Detection is Now Automatic

## For Claude Code CLI

**Just use the normal commands:**

```bash
make build
make run
```

That's it! These commands now automatically include:
- ✅ Build error detection and reporting
- ✅ Crash monitoring
- ✅ Auto-recovery after crashes
- ✅ Diagnostic reports

## You Don't Need To:
- ❌ Use special commands
- ❌ Remember new syntax
- ❌ Check if the app actually launched
- ❌ Manually detect crashes

## What You'll See

### Success:
```
✓ Build successful
✓ App launched
✓ App is stable and running
CLAUDE_CODE_SUCCESS: App running successfully
```

### Crash:
```
CRASH DETECTED (#1)
{
  "crash_type": "Metal Shader Error",
  "suggested_fixes": [...]
}
CLAUDE_CODE_CRASH: {full diagnostic data}
Attempting recovery...
```

### Build Failure:
```
✗ Build failed
CLAUDE_CODE_BUILD_FAILED: {
  "errors": ["error: missing ';'", ...],
  "log_file": "build/last_build.log"
}
```

## That's All!

The monitoring is completely transparent. Just use `make run` like you always have, and you'll automatically get intelligent crash handling and diagnostics.
