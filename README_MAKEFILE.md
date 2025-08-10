# MiniCity Makefile System

## Overview

The MiniCity Makefile serves as the "single source of truth" for all project operations, ensuring consistency across development sessions and team members.

## Quick Start

```bash
# Initial setup (run once)
make setup

# Daily development
make dev        # Start development session
make iterate    # Quick format, build, and run
make check      # Run all quality checks

# Before committing
make validate   # Full validation suite
```

## Core Commands

### Setup & Configuration

| Command | Description |
|---------|-------------|
| `make setup` | Complete project setup with dependencies |
| `make install-deps` | Install required tools (SwiftLint, etc.) |
| `make create-dirs` | Create project directory structure |
| `make setup-git-hooks` | Install pre-commit hooks |

### Build & Run

| Command | Description |
|---------|-------------|
| `make build` | Build debug version for simulator |
| `make build-release` | Build release version |
| `make run` | Build and run in simulator |
| `make run-release` | Run release build |
| `make run-device` | Run on physical device |
| `make debug` | Run with debugging enabled |

### Testing

| Command | Description |
|---------|-------------|
| `make test` | Run all tests |
| `make test-performance` | Run performance tests |
| `make test-ui` | Run UI tests |
| `make coverage` | Generate coverage report |
| `make benchmark-traffic` | Benchmark traffic simulation |

### Code Quality

| Command | Description |
|---------|-------------|
| `make check` | Run all quality checks |
| `make check-swift` | Run SwiftLint |
| `make format` | Auto-format code |
| `make analyze` | Static analysis |
| `make complexity` | Analyze code complexity |

### Debugging & Profiling

| Command | Description |
|---------|-------------|
| `make logs` | Stream app logs |
| `make crash-logs` | View crash logs |
| `make profile-gpu` | Capture GPU frame |
| `make profile-memory` | Memory profiling |
| `make debug-metal` | Debug Metal shaders |

### Asset Management

| Command | Description |
|---------|-------------|
| `make optimize-assets` | Optimize textures/images |
| `make generate-icons` | Generate app icons |
| `make download-assets` | Download game assets |
| `make check-assets` | Validate assets |

### Simulator Control

| Command | Description |
|---------|-------------|
| `make ensure-simulator` | Start simulator if needed |
| `make reset-simulator` | Reset to clean state |
| `make screenshot` | Take screenshot |
| `make record` | Record video |

### Documentation

| Command | Description |
|---------|-------------|
| `make docs` | Generate documentation |
| `make readme` | Update README stats |
| `make changelog` | Generate changelog |

### Metrics & Reporting

| Command | Description |
|---------|-------------|
| `make metrics` | Generate project metrics |
| `make report-performance` | Performance report |
| `make report-size` | App size report |
| `make city-stats` | City simulation stats |

### Deployment

| Command | Description |
|---------|-------------|
| `make archive` | Create release archive |
| `make export-ipa` | Export IPA file |
| `make beta` | Deploy to TestFlight |

### Workflows

| Command | Description |
|---------|-------------|
| `make dev` | Start development session |
| `make iterate` | Quick iteration cycle |
| `make validate` | Full validation before PR |
| `make daily` | Daily development tasks |
| `make release-prep` | Prepare for release |

### Cleanup

| Command | Description |
|---------|-------------|
| `make clean` | Clean build artifacts |
| `make clean-all` | Deep clean including caches |
| `make reset` | Complete reset |

## Advanced Usage

### Custom Arguments

Pass additional arguments to commands:

```bash
make run ARGS="--verbose"
make test ARGS="-only-testing:MiniCityTests/SpecificTest"
```

### Environment Variables

```bash
# Use different device
DEFAULT_DEVICE="iPhone 14 Pro" make run

# Use different OS version
DEFAULT_OS="16.0" make test
```

### Parallel Execution

Run multiple targets:

```bash
make -j4 check test metrics docs
```

## Helper Scripts

The Makefile uses several helper scripts in the `scripts/` directory:

### check-dependencies.sh

Verifies and installs all required dependencies:

```bash
./scripts/check-dependencies.sh
```

### monitor-performance.sh

Monitor real-time performance:

```bash
# Single snapshot
./scripts/monitor-performance.sh

# Continuous monitoring
./scripts/monitor-performance.sh --continuous

# Save report
./scripts/monitor-performance.sh --save
```

### test-city-features.sh

Run specific feature tests:

```bash
# Test everything
./scripts/test-city-features.sh all

# Test specific features
./scripts/test-city-features.sh metal
./scripts/test-city-features.sh traffic
./scripts/test-city-features.sh performance
```

## Configuration Files

### .swiftlint.yml

Configures SwiftLint rules for code quality:
- Enforces consistent style
- Catches common mistakes
- Custom rules for MiniCity

### ExportOptions.plist

Defines app export settings:
- Signing configuration
- Provisioning profiles
- Distribution method

## Git Hooks

The Makefile installs pre-commit hooks that:
1. Run SwiftLint checks
2. Validate assets
3. Run quick tests

To bypass hooks in emergencies:

```bash
git commit --no-verify
```

## Best Practices

1. **Daily Routine**
   ```bash
   make daily  # Start your day
   make dev    # Begin development
   make iterate # During development
   make validate # Before pushing
   ```

2. **Before Pull Requests**
   ```bash
   make validate
   make metrics
   make docs
   ```

3. **Performance Testing**
   ```bash
   make benchmark-traffic
   make profile-gpu
   make report-performance
   ```

4. **Release Preparation**
   ```bash
   make release-prep
   ```

## Troubleshooting

### Simulator Issues

```bash
make reset-simulator  # Reset if simulator is stuck
make ensure-simulator # Start if not running
```

### Build Issues

```bash
make clean-all  # Deep clean
make setup      # Reinstall dependencies
```

### Performance Issues

```bash
make profile-memory  # Check for leaks
make debug-metal    # Debug GPU issues
```

## Customization

Create a `Makefile.local` for personal overrides:

```makefile
# Makefile.local
DEFAULT_DEVICE = iPad Pro (12.9-inch)
DEFAULT_OS = 17.2
```

This file is automatically included but ignored by git.

## Contributing

When adding new Makefile targets:

1. Follow the naming convention (lowercase, hyphenated)
2. Add a help description with `##`
3. Use the color variables for output
4. Add to appropriate section
5. Update this README

## Performance Tips

- Use `make -j` for parallel execution
- Cache expensive operations in `build/` directory
- Use `--quiet` flags for faster execution
- Run `make clean` periodically to prevent cache issues

## Integration with CI/CD

The Makefile is designed to work with CI systems:

```yaml
# Example GitHub Actions
steps:
  - uses: actions/checkout@v2
  - run: make setup
  - run: make validate
  - run: make test
  - run: make archive
```

## Summary

The MiniCity Makefile system provides:

- ✅ Consistent development environment
- ✅ Automated quality checks
- ✅ Performance monitoring
- ✅ Asset management
- ✅ Testing automation
- ✅ Documentation generation
- ✅ Deployment preparation
- ✅ Debugging utilities

Use `make help` anytime to see available commands.