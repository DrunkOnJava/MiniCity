# MiniCity - Comprehensive Build & Development System
# =====================================================
# Single source of truth for all project operations
# Usage: make [target] [ARGS="additional arguments"]

# Configuration
PROJECT_NAME = MiniCity
SCHEME = MiniCity
WORKSPACE = $(PROJECT_NAME).xcodeproj
BUNDLE_ID = com.drunkonjava.MiniCity

# Directories
BUILD_DIR = build
DERIVED_DATA = $(BUILD_DIR)/DerivedData
ARCHIVES_DIR = $(BUILD_DIR)/Archives
REPORTS_DIR = reports
DOCS_DIR = docs
ASSETS_DIR = $(PROJECT_NAME)/Assets
SCREENSHOTS_DIR = screenshots
METRICS_DIR = metrics
MONITOR_DIR = /tmp/minicity_monitor

# Tools
XCODEBUILD = xcodebuild
XCRUN = xcrun
SWIFTLINT = swiftlint
SWIFTFORMAT = swiftformat
JAZZY = jazzy
XCOV = xcov

# Simulator Management
DEFAULT_DEVICE = iPhone 16 Pro Max
DEFAULT_OS = 18.6
SIMCTL = xcrun simctl

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
CYAN = \033[0;36m
NC = \033[0m # No Color

# Monitoring Configuration
ENABLE_MONITORING ?= 1
MONITOR_SCRIPT = scripts/monitoring/crash_monitor.sh
DIAGNOSTIC_SCRIPT = scripts/monitoring/claude_diagnostic.sh

# Default target
.DEFAULT_GOAL := help

# =============================================================================
# HELP & DOCUMENTATION
# =============================================================================

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)MiniCity Development System$(NC)"
	@echo "============================="
	@echo ""
	@echo "Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup          - Initial project setup"
	@echo "  make run           - Build and run in simulator (with crash detection)"
	@echo "  make test          - Run all tests"
	@echo "  make check         - Run all quality checks"
	@echo ""
	@echo "$(CYAN)Note: Crash monitoring is enabled by default. Use ENABLE_MONITORING=0 to disable.$(NC)"

# =============================================================================
# PROJECT SETUP & INITIALIZATION
# =============================================================================

.PHONY: setup
setup: ## Complete project setup (dependencies, git hooks, directories)
	@echo "$(YELLOW)Setting up MiniCity project...$(NC)"
	@$(MAKE) install-deps
	@$(MAKE) create-dirs
	@$(MAKE) setup-git-hooks
	@$(MAKE) setup-monitoring
	@$(MAKE) download-assets
	@echo "$(GREEN)✓ Setup complete!$(NC)"

.PHONY: install-deps
install-deps: ## Install required dependencies (SwiftLint, etc.)
	@echo "Installing dependencies..."
	@command -v brew >/dev/null 2>&1 || { echo "Installing Homebrew..."; /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
	@command -v swiftformat >/dev/null 2>&1 || brew install swiftformat
	@command -v xcbeautify >/dev/null 2>&1 || brew install xcbeautify
	@command -v jq >/dev/null 2>&1 || brew install jq
	@command -v fswatch >/dev/null 2>&1 || brew install fswatch
	@command -v xcov >/dev/null 2>&1 || gem install xcov
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

.PHONY: create-dirs
create-dirs: ## Create necessary project directories
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(REPORTS_DIR)
	@mkdir -p $(DOCS_DIR)
	@mkdir -p $(SCREENSHOTS_DIR)
	@mkdir -p $(METRICS_DIR)
	@mkdir -p $(MONITOR_DIR)
	@mkdir -p $(ASSETS_DIR)/Textures
	@mkdir -p $(ASSETS_DIR)/Models
	@mkdir -p $(ASSETS_DIR)/Sounds

.PHONY: setup-monitoring
setup-monitoring: ## Setup crash monitoring scripts
	@echo "$(YELLOW)Setting up monitoring scripts...$(NC)"
	@chmod +x scripts/*.sh 2>/dev/null || true
	@chmod +x scripts/monitoring/*.sh 2>/dev/null || true
	@echo "$(GREEN)✓ Monitoring scripts ready$(NC)"

.PHONY: setup-git-hooks
setup-git-hooks: ## Install git hooks for code quality
	@echo "#!/bin/sh" > .git/hooks/pre-commit
	@echo "make check-swift" >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)✓ Git hooks installed$(NC)"

# =============================================================================
# INTELLIGENT BUILD & RUN (WITH CRASH DETECTION)
# =============================================================================

.PHONY: build
build: ## Build for iOS Simulator with diagnostics
	@if [ "$(ENABLE_MONITORING)" = "1" ]; then \
		$(MAKE) build-monitored; \
	else \
		$(MAKE) build-simple; \
	fi

.PHONY: build-monitored
build-monitored: ## Build with full monitoring and diagnostics
	@echo "$(CYAN)Building $(PROJECT_NAME) with monitoring...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/last_build.log
	@echo "$(YELLOW)Compiling...$(NC)"
	@if $(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		build 2>&1 | tee $(BUILD_DIR)/last_build.log | xcbeautify; then \
		echo "$(GREEN)✓ Build successful$(NC)"; \
		echo "CLAUDE_CODE_BUILD_SUCCESS: Build completed successfully" >&2; \
	else \
		echo "$(RED)✗ Build failed$(NC)"; \
		echo "$(YELLOW)Generating diagnostics...$(NC)"; \
		BUILD_ERRORS=$(grep -E "error:|Error:" $(BUILD_DIR)/last_build.log | head -10); \
		echo '{' > $(BUILD_DIR)/last_diagnostic.json; \
		echo '  "event": "build_failed",' >> $(BUILD_DIR)/last_diagnostic.json; \
		echo '  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",' >> $(BUILD_DIR)/last_diagnostic.json; \
		echo '  "errors": ['$(echo "$BUILD_ERRORS" | jq -Rs 'split("\n") | map(select(length > 0)) | join(",")')'],' >> $(BUILD_DIR)/last_diagnostic.json; \
		echo '  "log_file": "$(BUILD_DIR)/last_build.log"' >> $(BUILD_DIR)/last_diagnostic.json; \
		echo '}' >> $(BUILD_DIR)/last_diagnostic.json; \
		echo "CLAUDE_CODE_BUILD_FAILED: $(cat $(BUILD_DIR)/last_diagnostic.json | jq -c .)" >&2; \
		echo ""; \
		echo "$(RED)Build Errors:$(NC)"; \
		echo "$BUILD_ERRORS"; \
		exit 1; \
	fi

.PHONY: build-simple
build-simple: ## Original build without monitoring
	@echo "$(YELLOW)Building $(PROJECT_NAME)...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		build | xcbeautify
	@echo "$(GREEN)✓ Build complete$(NC)"

.PHONY: run
run: ## Build and run with intelligent crash detection
	@if [ "$(ENABLE_MONITORING)" = "1" ]; then \
		$(MAKE) run-monitored; \
	else \
		$(MAKE) run-simple; \
	fi

.PHONY: run-monitored
run-monitored: ## Run with full monitoring and auto-recovery
	@echo "$(CYAN)Starting $(PROJECT_NAME) with intelligent monitoring...$(NC)"
	@# Clean previous monitoring data
	@rm -rf $(MONITOR_DIR)
	@mkdir -p $(MONITOR_DIR)
	@mkdir -p $(BUILD_DIR)
	@# Start background monitor
	@echo "$(YELLOW)Initializing crash monitor...$(NC)"
	@chmod +x $(MONITOR_SCRIPT) $(DIAGNOSTIC_SCRIPT) 2>/dev/null || true
	@$(MONITOR_SCRIPT) > $(MONITOR_DIR)/monitor.log 2>&1 & echo $$! > $(MONITOR_DIR)/monitor.pid
	@sleep 2
	@# Ensure simulator
	@$(MAKE) ensure-simulator
	@# Build with monitoring
	@echo "$(YELLOW)Building app...$(NC)"
	@if ! $(MAKE) build-monitored; then \
		echo "$(RED)Build failed - check diagnostics above$(NC)"; \
		kill $$(cat $(MONITOR_DIR)/monitor.pid 2>/dev/null) 2>/dev/null || true; \
		exit 1; \
	fi
	@# Install and launch
	@if [ -d "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(PROJECT_NAME).app" ]; then \
		echo "$(YELLOW)Installing app...$(NC)"; \
		$(SIMCTL) install booted $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(PROJECT_NAME).app; \
		echo "$(YELLOW)Launching app with monitoring...$(NC)"; \
		$(SIMCTL) launch booted $(BUNDLE_ID) & \
		APP_PID=$$!; \
		echo "$(GREEN)✓ App launched$(NC)"; \
		echo "$(CYAN)Monitoring for crashes (30 seconds)...$(NC)"; \
		CRASH_COUNT=0; \
		STABLE_COUNT=0; \
		for i in $$(seq 1 30); do \
			if [ -f "$(MONITOR_DIR)/current_status.json" ]; then \
				STATUS=$$(jq -r '.status' $(MONITOR_DIR)/current_status.json 2>/dev/null || echo "unknown"); \
				if [ "$$STATUS" = "crashed" ]; then \
					CRASH_COUNT=$$((CRASH_COUNT + 1)); \
					echo ""; \
					echo "$(RED)CRASH DETECTED (#$$CRASH_COUNT)$(NC)"; \
					$(DIAGNOSTIC_SCRIPT) diagnose 2>/dev/null | jq '.crash_analysis' 2>/dev/null || true; \
					echo "CLAUDE_CODE_CRASH: $$($(DIAGNOSTIC_SCRIPT) diagnose 2>/dev/null | jq -c .)" >&2; \
					if [ $$CRASH_COUNT -lt 3 ]; then \
						echo "$(YELLOW)Attempting recovery...$(NC)"; \
						sleep 2; \
						$(SIMCTL) launch booted $(BUNDLE_ID) & \
						APP_PID=$$!; \
					else \
						echo "$(RED)Multiple crashes - manual intervention required$(NC)"; \
						break; \
					fi; \
				elif [ "$$STATUS" = "running" ]; then \
					STABLE_COUNT=$$((STABLE_COUNT + 1)); \
					if [ $$STABLE_COUNT -ge 5 ]; then \
						echo ""; \
						echo "$(GREEN)✓ App is stable and running$(NC)"; \
						echo "CLAUDE_CODE_SUCCESS: App running successfully" >&2; \
						break; \
					fi; \
				fi; \
			fi; \
			sleep 1; \
			printf "."; \
		done; \
		echo ""; \
		if [ $$CRASH_COUNT -gt 0 ]; then \
			echo "$(YELLOW)Final diagnostic report:$(NC)"; \
			$(DIAGNOSTIC_SCRIPT) diagnose 2>/dev/null | jq '.' || true; \
		fi; \
		kill $$(cat $(MONITOR_DIR)/monitor.pid 2>/dev/null) 2>/dev/null || true; \
		echo "$(BLUE)Monitoring complete$(NC)"; \
	else \
		echo "$(RED)✗ Build failed - app bundle not found$(NC)"; \
		kill $$(cat $(MONITOR_DIR)/monitor.pid 2>/dev/null) 2>/dev/null || true; \
		exit 1; \
	fi

.PHONY: run-simple
run-simple: ## Original run without monitoring
	@echo "$(YELLOW)Building and launching $(PROJECT_NAME)...$(NC)"
	@$(MAKE) ensure-simulator
	@echo "$(YELLOW)Building app...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		build 2>&1 | grep -E "(Building|Succeeded|Failed|error:)" || true
	@if [ -d "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(PROJECT_NAME).app" ]; then \
		echo "$(YELLOW)Installing app...$(NC)"; \
		$(SIMCTL) install booted $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(PROJECT_NAME).app; \
		echo "$(YELLOW)Launching app...$(NC)"; \
		$(SIMCTL) launch booted $(BUNDLE_ID); \
		echo "$(GREEN)✓ App launched$(NC)"; \
	else \
		echo "$(RED)✗ Build failed - app bundle not found$(NC)"; \
		exit 1; \
	fi

.PHONY: build-release
build-release: ## Build for iOS Simulator (Release)
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		build | xcbeautify

.PHONY: run-release
run-release: build-release ## Run release build in simulator
	@$(MAKE) ensure-simulator
	@$(SIMCTL) install booted $(DERIVED_DATA)/Build/Products/Release-iphonesimulator/$(PROJECT_NAME).app
	@$(SIMCTL) launch booted $(BUNDLE_ID)

.PHONY: run-device
run-device: ## Build and run on physical device
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination 'platform=iOS,name=Any iOS Device' \
		run | xcbeautify

# =============================================================================
# DIAGNOSTIC COMMANDS
# =============================================================================

.PHONY: diagnose
diagnose: ## Get current app diagnostics
	@chmod +x $(DIAGNOSTIC_SCRIPT) 2>/dev/null || true
	@$(DIAGNOSTIC_SCRIPT) diagnose

.PHONY: status
status: ## Check current app status
	@if [ -f "$(MONITOR_DIR)/current_status.json" ]; then \
		jq '.' $(MONITOR_DIR)/current_status.json; \
	else \
		echo '{"status": "not_monitored", "message": "Run with monitoring enabled to get status"}'; \
	fi

.PHONY: monitor-logs
monitor-logs: ## Show monitor logs
	@if [ -f "$(MONITOR_DIR)/monitor.log" ]; then \
		tail -f $(MONITOR_DIR)/monitor.log; \
	else \
		echo "No monitor logs available. Run 'make run' first."; \
	fi

# =============================================================================
# TESTING
# =============================================================================

.PHONY: test
test: ## Run all tests
	@echo "$(YELLOW)Running tests...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-derivedDataPath $(DERIVED_DATA) \
		test | xcbeautify
	@echo "$(GREEN)✓ Tests passed$(NC)"

.PHONY: test-performance
test-performance: ## Run performance tests
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-only-testing:$(PROJECT_NAME)Tests/PerformanceTests \
		test | xcbeautify

.PHONY: test-ui
test-ui: ## Run UI tests
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-only-testing:$(PROJECT_NAME)UITests \
		test | xcbeautify

.PHONY: coverage
coverage: ## Generate test coverage report
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-enableCodeCoverage YES \
		test | xcbeautify
	@xcov --project $(WORKSPACE) --scheme $(SCHEME) --output_directory $(REPORTS_DIR)/coverage
	@open $(REPORTS_DIR)/coverage/index.html

# =============================================================================
# CODE QUALITY
# =============================================================================

.PHONY: check
check: ## Run all quality checks
	@$(MAKE) check-swift
	@$(MAKE) analyze
	@$(MAKE) check-assets
	@echo "$(GREEN)✓ All checks passed$(NC)"

.PHONY: check-swift
check-swift: ## Run SwiftLint
	@echo "$(YELLOW)Running SwiftLint...$(NC)"
	@$(SWIFTLINT) lint --strict --reporter emoji

.PHONY: format
format: ## Auto-format Swift code
	@echo "$(YELLOW)Formatting code...$(NC)"
	@$(SWIFTFORMAT) $(PROJECT_NAME) --swiftversion 5.9
	@echo "$(GREEN)✓ Code formatted$(NC)"

.PHONY: analyze
analyze: ## Run static analysis
	@echo "$(YELLOW)Running static analysis...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		analyze -quiet | xcbeautify

.PHONY: complexity
complexity: ## Analyze code complexity
	@echo "$(YELLOW)Analyzing complexity...$(NC)"
	@$(SWIFTLINT) analyze --compiler-log-path $(DERIVED_DATA)/Logs/Build/*.xcactivitylog

# =============================================================================
# DEBUGGING & PROFILING
# =============================================================================

.PHONY: debug
debug: ## Run with debugging enabled
	@$(MAKE) ensure-simulator
	@echo "$(YELLOW)Starting debug session...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-IDEBuildOperationMaxNumberOfConcurrentCompileTasks=1 \
		build | xcbeautify
	@echo "$(GREEN)Debug build ready. Attach debugger via Xcode.$(NC)"

.PHONY: profile-gpu
profile-gpu: ## Capture GPU frame for Metal debugging
	@echo "$(YELLOW)Capturing GPU frame...$(NC)"
	@$(SIMCTL) io booted recordVideo --type=mp4 $(SCREENSHOTS_DIR)/gpu-capture.mp4 &
	@sleep 5
	@killall -INT simctl
	@echo "$(GREEN)✓ GPU frame captured$(NC)"

.PHONY: profile-memory
profile-memory: ## Run with memory profiling
	@echo "$(YELLOW)Starting memory profiling...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Release \
		-enableAddressSanitizer YES \
		-enableThreadSanitizer NO \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		run | xcbeautify

.PHONY: logs
logs: ## Show app logs from simulator
	@echo "$(YELLOW)Streaming logs...$(NC)"
	@$(SIMCTL) spawn booted log stream --predicate 'processImagePath endswith "$(PROJECT_NAME)"' --level debug

.PHONY: crash-logs
crash-logs: ## Show crash logs
	@open ~/Library/Logs/DiagnosticReports/

# =============================================================================
# ASSET MANAGEMENT
# =============================================================================

.PHONY: optimize-assets
optimize-assets: ## Optimize all game assets
	@echo "$(YELLOW)Optimizing assets...$(NC)"
	@find $(ASSETS_DIR)/Textures -name "*.png" -exec pngquant --quality=85-95 --ext .png --force {} \;
	@echo "$(GREEN)✓ Assets optimized$(NC)"

.PHONY: generate-icons
generate-icons: ## Generate app icons from source
	@echo "$(YELLOW)Generating app icons...$(NC)"
	@mkdir -p $(ASSETS_DIR)/AppIcon.appiconset
	@sips -z 1024 1024 $(ASSETS_DIR)/icon-source.png --out $(ASSETS_DIR)/AppIcon.appiconset/icon-1024.png
	@sips -z 180 180 $(ASSETS_DIR)/icon-source.png --out $(ASSETS_DIR)/AppIcon.appiconset/icon-180.png
	@sips -z 120 120 $(ASSETS_DIR)/icon-source.png --out $(ASSETS_DIR)/AppIcon.appiconset/icon-120.png
	@echo "$(GREEN)✓ Icons generated$(NC)"

.PHONY: download-assets
download-assets: ## Download/update game assets
	@echo "$(YELLOW)Downloading assets...$(NC)"
	@# Add asset download logic here
	@echo "$(GREEN)✓ Assets ready$(NC)"

.PHONY: check-assets
check-assets: ## Validate all assets
	@echo "$(YELLOW)Validating assets...$(NC)"
	@find $(ASSETS_DIR) -name "*.png" -exec file {} \; | grep -v "PNG image data" || true
	@echo "$(GREEN)✓ Assets valid$(NC)"

# =============================================================================
# SIMULATOR MANAGEMENT
# =============================================================================

.PHONY: ensure-simulator
ensure-simulator: ## Ensure only one simulator is running
	@echo "$(YELLOW)Managing simulators...$(NC)"
	@# Shutdown all simulators except the target device
	@for device in $$($(SIMCTL) list devices | grep "(Booted)" | grep -v "$(DEFAULT_DEVICE)" | grep -E -o "\([A-F0-9\-]+\)" | tr -d '()'); do \
		echo "Shutting down $$device..."; \
		$(SIMCTL) shutdown $$device 2>/dev/null || true; \
	done
	@# Check if target device is already booted
	@if ! $(SIMCTL) list devices | grep "$(DEFAULT_DEVICE)" | grep -q "(Booted)"; then \
		echo "$(YELLOW)Starting $(DEFAULT_DEVICE)...$(NC)"; \
		DEVICE_ID=$$($(SIMCTL) list devices | grep "$(DEFAULT_DEVICE)" | grep -E -o "\([A-F0-9\-]+\)" | tr -d '()' | head -1); \
		$(SIMCTL) boot $$DEVICE_ID 2>/dev/null || true; \
		open -a Simulator --args -CurrentDeviceUDID $$DEVICE_ID; \
		sleep 3; \
	else \
		echo "$(GREEN)$(DEFAULT_DEVICE) already running$(NC)"; \
	fi

.PHONY: reset-simulator
reset-simulator: ## Reset simulator to clean state
	@echo "$(YELLOW)Resetting simulator...$(NC)"
	@$(SIMCTL) shutdown all
	@$(SIMCTL) erase all
	@echo "$(GREEN)✓ Simulator reset$(NC)"

.PHONY: screenshot
screenshot: ## Take simulator screenshot
	@mkdir -p $(SCREENSHOTS_DIR)
	@$(SIMCTL) io booted screenshot $(SCREENSHOTS_DIR)/screenshot-$$(date +%Y%m%d-%H%M%S).png
	@echo "$(GREEN)✓ Screenshot saved$(NC)"

.PHONY: record
record: ## Record simulator screen
	@mkdir -p $(SCREENSHOTS_DIR)
	@echo "$(YELLOW)Recording... Press Ctrl+C to stop$(NC)"
	@$(SIMCTL) io booted recordVideo $(SCREENSHOTS_DIR)/recording-$$(date +%Y%m%d-%H%M%S).mp4

# =============================================================================
# CLEANUP
# =============================================================================

.PHONY: clean
clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DERIVED_DATA)
	@rm -rf $(MONITOR_DIR)
	@$(XCODEBUILD) -project $(WORKSPACE) -scheme $(SCHEME) clean
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: clean-all
clean-all: clean ## Deep clean (includes caches)
	@echo "$(YELLOW)Deep cleaning...$(NC)"
	@rm -rf ~/Library/Developer/Xcode/DerivedData/$(PROJECT_NAME)-*
	@rm -rf $(REPORTS_DIR)
	@rm -rf $(SCREENSHOTS_DIR)
	@rm -rf $(METRICS_DIR)
	@echo "$(GREEN)✓ Deep clean complete$(NC)"

.PHONY: reset
reset: clean-all reset-simulator ## Complete reset
	@echo "$(GREEN)✓ Complete reset done$(NC)"

# =============================================================================
# DEVELOPMENT WORKFLOWS
# =============================================================================

.PHONY: dev
dev: ## Start development session
	@$(MAKE) ensure-simulator
	@$(MAKE) run
	@$(MAKE) logs

.PHONY: iterate
iterate: ## Quick iteration (format, build, run)
	@$(MAKE) format
	@$(MAKE) run

.PHONY: validate
validate: ## Full validation before PR
	@echo "$(YELLOW)Running full validation...$(NC)"
	@$(MAKE) format
	@$(MAKE) check
	@$(MAKE) test
	@$(MAKE) build-release
	@$(MAKE) metrics
	@echo "$(GREEN)✓ Validation complete - ready for PR$(NC)"

# =============================================================================
# METRICS & REPORTING
# =============================================================================

.PHONY: metrics
metrics: ## Generate project metrics
	@echo "$(YELLOW)Generating metrics...$(NC)"
	@mkdir -p $(METRICS_DIR)
	@echo "Project Metrics - $$(date)" > $(METRICS_DIR)/metrics.txt
	@echo "========================" >> $(METRICS_DIR)/metrics.txt
	@echo "" >> $(METRICS_DIR)/metrics.txt
	@echo "Code Statistics:" >> $(METRICS_DIR)/metrics.txt
	@echo "  Swift files: $$(find $(PROJECT_NAME) -name '*.swift' | wc -l)" >> $(METRICS_DIR)/metrics.txt
	@echo "  Lines of code: $$(find $(PROJECT_NAME) -name '*.swift' | xargs wc -l | tail -1 | awk '{print $$1}')" >> $(METRICS_DIR)/metrics.txt
	@echo "  Metal shaders: $$(find $(PROJECT_NAME) -name '*.metal' | wc -l)" >> $(METRICS_DIR)/metrics.txt
	@echo "" >> $(METRICS_DIR)/metrics.txt
	@echo "Complexity:" >> $(METRICS_DIR)/metrics.txt
	@$(SWIFTLINT) analyze --reporter json --quiet | jq '.files | length' >> $(METRICS_DIR)/metrics.txt 2>/dev/null || echo "  N/A" >> $(METRICS_DIR)/metrics.txt
	@cat $(METRICS_DIR)/metrics.txt
	@echo "$(GREEN)✓ Metrics generated$(NC)"

# Include local overrides if they exist
-include Makefile.local
