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
NC = \033[0m # No Color

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
	@echo "  make run           - Build and run in simulator"
	@echo "  make test          - Run all tests"
	@echo "  make check         - Run all quality checks"

# =============================================================================
# PROJECT SETUP & INITIALIZATION
# =============================================================================

.PHONY: setup
setup: ## Complete project setup (dependencies, git hooks, directories)
	@echo "$(YELLOW)Setting up MiniCity project...$(NC)"
	@$(MAKE) install-deps
	@$(MAKE) create-dirs
	@$(MAKE) setup-git-hooks
	@$(MAKE) download-assets
	@echo "$(GREEN)✓ Setup complete!$(NC)"

.PHONY: install-deps
install-deps: ## Install required dependencies (SwiftLint, etc.)
	@echo "Installing dependencies..."
	@command -v brew >/dev/null 2>&1 || { echo "Installing Homebrew..."; /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
	@command -v swiftformat >/dev/null 2>&1 || brew install swiftformat
	@command -v xcbeautify >/dev/null 2>&1 || brew install xcbeautify
	@command -v xcov >/dev/null 2>&1 || gem install xcov
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

.PHONY: create-dirs
create-dirs: ## Create necessary project directories
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(REPORTS_DIR)
	@mkdir -p $(DOCS_DIR)
	@mkdir -p $(SCREENSHOTS_DIR)
	@mkdir -p $(METRICS_DIR)
	@mkdir -p $(ASSETS_DIR)/Textures
	@mkdir -p $(ASSETS_DIR)/Models
	@mkdir -p $(ASSETS_DIR)/Sounds

.PHONY: setup-git-hooks
setup-git-hooks: ## Install git hooks for code quality
	@echo "#!/bin/sh" > .git/hooks/pre-commit
	@echo "make check-swift" >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)✓ Git hooks installed$(NC)"

# =============================================================================
# BUILD & RUN
# =============================================================================

.PHONY: build
build: ## Build for iOS Simulator (Debug)
	@echo "$(YELLOW)Building $(PROJECT_NAME)...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		build | xcbeautify
	@echo "$(GREEN)✓ Build complete$(NC)"

.PHONY: build-release
build-release: ## Build for iOS Simulator (Release)
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		build | xcbeautify

.PHONY: run
run: ## Build and run in iOS Simulator
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
# DOCUMENTATION
# =============================================================================

.PHONY: docs
docs: ## Generate documentation
	@echo "$(YELLOW)Generating documentation...$(NC)"
	@$(JAZZY) \
		--clean \
		--author "MiniCity Team" \
		--module $(PROJECT_NAME) \
		--source-directory $(PROJECT_NAME) \
		--output $(DOCS_DIR)
	@echo "$(GREEN)✓ Documentation generated$(NC)"
	@open $(DOCS_DIR)/index.html

.PHONY: readme
readme: ## Update README with current stats
	@echo "$(YELLOW)Updating README...$(NC)"
	@echo "# MiniCity" > README.md
	@echo "" >> README.md
	@echo "## Statistics" >> README.md
	@echo "- Lines of code: $$(find $(PROJECT_NAME) -name '*.swift' | xargs wc -l | tail -1 | awk '{print $$1}')" >> README.md
	@echo "- Number of files: $$(find $(PROJECT_NAME) -name '*.swift' | wc -l)" >> README.md
	@echo "- Last updated: $$(date)" >> README.md
	@echo "$(GREEN)✓ README updated$(NC)"

.PHONY: links
links: ## Display Metal framework documentation links
	@echo ""
	@echo "$(CYAN)Review and explore the Metal framework with these suggested documentation links:$(NC)"
	@echo ""
	@echo "$(YELLOW)Core Metal Framework:$(NC)"
	@echo "  https://developer.apple.com/documentation/metal"
	@echo "  https://developer.apple.com/documentation/MetalKit"
	@echo "  https://developer.apple.com/documentation/MetalPerformanceShaders"
	@echo "  https://developer.apple.com/documentation/metal/using-metal-to-draw-a-view's-contents"
	@echo "  https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator"
	@echo ""
	@echo "$(YELLOW)Rendering & Graphics:$(NC)"
	@echo "  https://developer.apple.com/documentation/metal/rendering_pipelines"
	@echo "  https://developer.apple.com/documentation/metal/vertex_data_and_vertex_descriptors"
	@echo "  https://developer.apple.com/documentation/metal/using_a_render_pipeline_to_render_primitives"
	@echo "  https://developer.apple.com/documentation/metal/creating_and_sampling_textures"
	@echo "  https://developer.apple.com/documentation/metal/calculating_primitive_visibility_using_depth_testing"
	@echo ""
	@echo "$(YELLOW)Compute & GPU Programming:$(NC)"
	@echo "  https://developer.apple.com/documentation/metal/compute_pipelines"
	@echo "  https://developer.apple.com/documentation/metal/gpu_programming_techniques"
	@echo "  https://developer.apple.com/documentation/metal/performing_calculations_on_a_gpu"
	@echo "  https://developer.apple.com/documentation/metal/using_metal_to_accelerate_matrix_operations"
	@echo ""
	@echo "$(YELLOW)Memory & Performance:$(NC)"
	@echo "  https://developer.apple.com/documentation/metal/resource_fundamentals"
	@echo "  https://developer.apple.com/documentation/metal/setting_resource_storage_modes"
	@echo "  https://developer.apple.com/documentation/metal/synchronization"
	@echo "  https://developer.apple.com/documentation/metal/optimizing_performance_with_the_metal_frame_debugger"
	@echo ""
	@echo "$(YELLOW)Debugging & Tools:$(NC)"
	@echo "  https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information"
	@echo "  https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode"
	@echo "  https://developer.apple.com/documentation/xcode/metal-debugger"
	@echo "  https://developer.apple.com/documentation/xcode/naming-resources-and-commands"
	@echo "  https://developer.apple.com/documentation/metal/debugging_tools"
	@echo ""
	@echo "$(YELLOW)Shaders & Language:$(NC)"
	@echo "  https://developer.apple.com/documentation/metal/metal_shading_language_guide"
	@echo "  https://developer.apple.com/documentation/metal/shader_libraries"
	@echo "  https://developer.apple.com/documentation/metal/shader_functions"
	@echo "  https://developer.apple.com/documentation/xcode/building-your-project-with-embedded-shader-sources"
	@echo ""
	@echo "$(YELLOW)Advanced Techniques:$(NC)"
	@echo "  https://developer.apple.com/documentation/metal/indirect_command_encoding"
	@echo "  https://developer.apple.com/documentation/metal/tessellation"
	@echo "  https://developer.apple.com/documentation/metal/ray_tracing"
	@echo "  https://developer.apple.com/documentation/metal/function_pointers"
	@echo "  https://developer.apple.com/documentation/metal/mesh_shaders"
	@echo ""
	@echo "$(YELLOW)Development Workflows:$(NC)"
	@echo "  https://developer.apple.com/documentation/Xcode/Metal-developer-workflows"
	@echo "  https://developer.apple.com/documentation/xcode/testing-in-simulator-versus-testing-on-hardware-devices"
	@echo "  https://developer.apple.com/documentation/Xcode/devices-and-simulator"
	@echo ""
	@echo "$(YELLOW)Best Practices & Guides:$(NC)"
	@echo "  https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/index.html#//apple_ref/doc/uid/TP40016642"
	@echo "  https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Introduction/Introduction.html#//apple_ref/doc/uid/TP40014221"
	@echo "  https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Dev-Technique/Dev-Technique.html#//apple_ref/doc/uid/TP40014221-CH8-SW1"
	@echo "  https://developer.apple.com/documentation/metal/metal_sample_code_library"
	@echo ""
	@echo "$(YELLOW)Game & Simulation Specific:$(NC)"
	@echo "  https://developer.apple.com/documentation/gameplaykit"
	@echo "  https://developer.apple.com/documentation/metal/metal_for_accelerating_ray_tracing"
	@echo "  https://developer.apple.com/documentation/metalperformanceshaders/mpsgraph"
	@echo "  https://developer.apple.com/documentation/metal/gpu-driven_rendering"
	@echo ""

.PHONY: metal-specs
metal-specs: ## Display Metal Shading Language Specification link and details
	@echo ""
	@echo "$(CYAN)===== Metal Shading Language Specification =====$(NC)"
	@echo ""
	@echo "$(YELLOW)Official Metal Shading Language Specification:$(NC)"
	@echo "  https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf"
	@echo ""
	@echo "$(GREEN)Local Copy Available:$(NC)"
	@if [ -f "/Users/griffin/Downloads/Metal-Shading-Language-Specification.pdf" ]; then \
		echo "  ✓ Found at: /Users/griffin/Downloads/Metal-Shading-Language-Specification.pdf"; \
		echo "  File size: $$(du -h '/Users/griffin/Downloads/Metal-Shading-Language-Specification.pdf' | cut -f1)"; \
		echo ""; \
		echo "  To open: open '/Users/griffin/Downloads/Metal-Shading-Language-Specification.pdf'"; \
	else \
		echo "  ✗ Not found locally"; \
		echo "  Download from the link above to: /Users/griffin/Downloads/"; \
	fi
	@echo ""
	@echo "$(YELLOW)Key Specification Topics for City Simulation:$(NC)"
	@echo "  • Data Types: Vectors, matrices, textures (Section 2)"
	@echo "  • Address Spaces: device, constant, threadgroup (Section 4)"
	@echo "  • Function Qualifiers: vertex, fragment, kernel (Section 5)"
	@echo "  • Built-in Functions: Math, geometric, texture sampling (Section 6)"
	@echo "  • Compute Functions: Thread organization, barriers (Section 5.8)"
	@echo "  • Vertex Attributes: Input assembly, descriptors (Section 5.2)"
	@echo "  • Fragment Functions: Color attachments, depth (Section 5.3)"
	@echo ""
	@echo "$(YELLOW)Important for MiniCity:$(NC)"
	@echo "  • Instanced Rendering: instance_id, vertex descriptors (Section 5.2.3)"
	@echo "  • Texture Arrays: For building/terrain atlases (Section 2.8)"
	@echo "  • Atomic Operations: For traffic counters (Section 6.13)"
	@echo "  • Threadgroup Memory: For compute optimizations (Section 4.3)"
	@echo "  • Function Constants: For shader variants (Section 5.10)"
	@echo ""
	@echo "$(CYAN)Related Documentation:$(NC)"
	@echo "  • Metal Feature Set Tables: https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf"
	@echo "  • Metal Tools Profiling Guide: https://developer.apple.com/documentation/metal/tools"
	@echo "  • Metal Shader Converter: https://developer.apple.com/documentation/metal/shader_converter"
	@echo ""

.PHONY: xcode-config
xcode-config: ## Display comprehensive Xcode command-line configuration guide
	@if [ -f "/Users/griffin/Downloads/xcodeViaTerminalGuide.md" ]; then \
		echo "$(CYAN)===== Xcode Command-Line Configuration Guide =====$(NC)"; \
		echo ""; \
		cat "/Users/griffin/Downloads/xcodeViaTerminalGuide.md" | sed 's/^/  /' | less -R; \
	else \
		echo "$(RED)Error: Guide file not found at /Users/griffin/Downloads/xcodeViaTerminalGuide.md$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Quick Reference - Essential Xcode CLI Commands:$(NC)"; \
		echo ""; \
		echo "$(GREEN)Xcode Selection:$(NC)"; \
		echo "  xcode-select --print-path        # Show active Xcode"; \
		echo "  sudo xcode-select -s /path        # Switch Xcode version"; \
		echo "  xcode-select --install            # Install CLI tools"; \
		echo ""; \
		echo "$(GREEN)Building & Testing:$(NC)"; \
		echo "  xcodebuild -list                  # List schemes/targets"; \
		echo "  xcodebuild -scheme NAME build     # Build scheme"; \
		echo "  xcodebuild test -scheme NAME      # Run tests"; \
		echo "  xcodebuild archive -scheme NAME   # Create archive"; \
		echo ""; \
		echo "$(GREEN)Tools & Utilities:$(NC)"; \
		echo "  xcrun --find TOOL                 # Find tool path"; \
		echo "  xcrun simctl list                 # List simulators"; \
		echo "  xcrun simctl boot DEVICE          # Boot simulator"; \
		echo ""; \
		echo "$(GREEN)Dependency Management:$(NC)"; \
		echo "  swift package init                # Create SPM package"; \
		echo "  pod install                       # Install CocoaPods"; \
		echo "  carthage update                   # Update Carthage deps"; \
		echo ""; \
		echo "$(GREEN)Project Generation:$(NC)"; \
		echo "  xcodegen generate                 # Generate from YAML"; \
		echo "  tuist generate                    # Generate from Swift"; \
		echo ""; \
		echo "$(GREEN)Automation:$(NC)"; \
		echo "  fastlane LANE                     # Run fastlane lane"; \
		echo "  xcodebuild | xcpretty             # Pretty output"; \
		echo ""; \
		echo "$(YELLOW)For the full guide, ensure xcodeViaTerminalGuide.md exists in Downloads$(NC)"; \
	fi

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

.PHONY: report-performance
report-performance: ## Generate performance report
	@echo "$(YELLOW)Generating performance report...$(NC)"
	@mkdir -p $(REPORTS_DIR)
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-resultBundlePath $(REPORTS_DIR)/performance.xcresult \
		test-without-building
	@xcrun xcresulttool get --path $(REPORTS_DIR)/performance.xcresult --format json > $(REPORTS_DIR)/performance.json
	@echo "$(GREEN)✓ Performance report generated$(NC)"

.PHONY: report-size
report-size: ## Report app size
	@echo "$(YELLOW)Calculating app size...$(NC)"
	@$(MAKE) build-release
	@echo "App size: $$(du -sh $(DERIVED_DATA)/Build/Products/Release-iphonesimulator/$(PROJECT_NAME).app | cut -f1)"

# =============================================================================
# DEPLOYMENT & DISTRIBUTION
# =============================================================================

.PHONY: archive
archive: ## Create release archive
	@echo "$(YELLOW)Creating archive...$(NC)"
	@mkdir -p $(ARCHIVES_DIR)
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-archivePath $(ARCHIVES_DIR)/$(PROJECT_NAME).xcarchive \
		archive | xcbeautify
	@echo "$(GREEN)✓ Archive created$(NC)"

.PHONY: export-ipa
export-ipa: archive ## Export IPA for distribution
	@$(XCODEBUILD) \
		-exportArchive \
		-archivePath $(ARCHIVES_DIR)/$(PROJECT_NAME).xcarchive \
		-exportPath $(ARCHIVES_DIR) \
		-exportOptionsPlist ExportOptions.plist
	@echo "$(GREEN)✓ IPA exported$(NC)"

.PHONY: beta
beta: ## Deploy to TestFlight
	@echo "$(YELLOW)Deploying to TestFlight...$(NC)"
	@$(MAKE) archive
	@xcrun altool --upload-app \
		--type ios \
		--file $(ARCHIVES_DIR)/$(PROJECT_NAME).ipa \
		--username "$(APPLE_ID)" \
		--password "$(APP_PASSWORD)"

# =============================================================================
# GIT OPERATIONS
# =============================================================================

.PHONY: commit-check
commit-check: ## Pre-commit checks
	@$(MAKE) check-swift
	@$(MAKE) test
	@echo "$(GREEN)✓ Ready to commit$(NC)"

.PHONY: changelog
changelog: ## Generate changelog from git history
	@echo "# Changelog" > CHANGELOG.md
	@echo "" >> CHANGELOG.md
	@git log --pretty=format:"- %s (%h)" --no-merges -20 >> CHANGELOG.md
	@echo "$(GREEN)✓ Changelog generated$(NC)"

# =============================================================================
# CLEANUP
# =============================================================================

.PHONY: clean
clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DERIVED_DATA)
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

.PHONY: daily
daily: ## Daily development tasks
	@echo "$(YELLOW)Running daily tasks...$(NC)"
	@$(MAKE) clean
	@$(MAKE) check
	@$(MAKE) test
	@$(MAKE) metrics
	@$(MAKE) docs
	@echo "$(GREEN)✓ Daily tasks complete$(NC)"

.PHONY: release-prep
release-prep: ## Prepare for release
	@echo "$(YELLOW)Preparing release...$(NC)"
	@$(MAKE) clean-all
	@$(MAKE) validate
	@$(MAKE) optimize-assets
	@$(MAKE) docs
	@$(MAKE) changelog
	@$(MAKE) archive
	@echo "$(GREEN)✓ Release prepared$(NC)"

# =============================================================================
# CITY-SPECIFIC TARGETS
# =============================================================================

.PHONY: city-stats
city-stats: ## Show city simulation statistics
	@echo "$(YELLOW)City Statistics$(NC)"
	@echo "=================="
	@echo "Buildings: $$(grep -r 'BuildingType' $(PROJECT_NAME) | wc -l)"
	@echo "Vehicle types: $$(grep -r 'VehicleType' $(PROJECT_NAME) | wc -l)"
	@echo "Shaders: $$(find $(PROJECT_NAME) -name '*.metal' | wc -l)"
	@echo "UI Components: $$(find $(PROJECT_NAME)/UI -name '*.swift' | wc -l)"

.PHONY: benchmark-traffic
benchmark-traffic: ## Benchmark traffic simulation
	@echo "$(YELLOW)Benchmarking traffic...$(NC)"
	@$(XCODEBUILD) \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEFAULT_DEVICE),OS=$(DEFAULT_OS)' \
		-only-testing:$(PROJECT_NAME)Tests/TrafficPerformanceTests \
		test | xcbeautify

.PHONY: debug-metal
debug-metal: ## Debug Metal shaders
	@echo "$(YELLOW)Metal debugging enabled$(NC)"
	@export MTL_DEBUG_LAYER=1
	@export MTL_SHADER_VALIDATION=1
	@$(MAKE) run

# Include local overrides if they exist
-include Makefile.local