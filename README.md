# MiniCity

![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue)
![Metal](https://img.shields.io/badge/Metal-3%2F4-orange)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![GameplayKit](https://img.shields.io/badge/GameplayKit-✓-green)

A SimCity 4-inspired city building simulation for iOS with Cities: Skylines-level features, built using Metal 3/4 and GameplayKit.

## 🎮 Features

- **Pure Metal Rendering** - GPU-accelerated graphics with Metal 3/4
- **GameplayKit AI Traffic** - Intelligent agent-based traffic simulation
- **Google Maps-style Controls** - Intuitive multitouch camera system
- **Dynamic City Growth** - Real-time building placement and city evolution
- **HUD Overlay System** - Interactive building placement interface
- **Optimized Performance** - 60 FPS with hundreds of vehicles and buildings

## 🚀 Quick Start

### Prerequisites

```bash
# Install Xcode and command-line tools
xcode-select --install

# Run automatic setup
make setup
```

### Build & Run

```bash
# Start development session
make dev

# Or just build and run
make run
```

## 📚 Comprehensive Makefile System

MiniCity uses a robust Makefile as the "single source of truth" for all operations:

### Essential Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make setup` | Complete project setup |
| `make dev` | Start development session |
| `make run` | Build and run in simulator |
| `make test` | Run all tests |
| `make validate` | Full validation before PR |

### Development Workflow

```bash
# Daily development cycle
make daily          # Run daily tasks
make iterate        # Quick edit-build-run
make check          # Quality checks

# Before committing
make commit-check   # Pre-commit validation
make validate       # Full validation suite
```

### Metal Development

```bash
# Metal framework resources
make links          # Display Metal documentation links
make metal-specs    # Show Metal Shading Language specs
make debug-metal    # Debug shaders with validation

# Performance profiling
make profile-gpu    # Capture GPU frame
make profile-memory # Memory analysis
make benchmark-traffic # Traffic simulation benchmarks
```

### Testing & Quality

```bash
# Testing
make test           # Run all tests
make test-ui        # UI tests only
make coverage       # Generate coverage report

# Code quality
make check-swift    # SwiftLint checks
make format         # Auto-format code
make analyze        # Static analysis
make complexity     # Code complexity analysis
```

### Asset Management

```bash
make optimize-assets  # Optimize textures
make generate-icons   # Generate app icons
make check-assets     # Validate assets
```

### Documentation & Metrics

```bash
make docs            # Generate documentation
make metrics         # Project metrics
make city-stats      # City simulation statistics
make changelog       # Generate changelog
```

## 🏗️ Architecture

### Core Components

- **MetalEngine** - Core rendering engine with instanced drawing
- **GameplayKitTrafficSimulation** - Agent-based traffic AI
- **CameraController** - Multitouch gesture handling
- **HUDOverlay** - Building placement interface
- **CityGameController** - Main game logic coordinator

### Technology Stack

- **Rendering**: Metal 3/4, MetalKit
- **AI/Simulation**: GameplayKit (GKAgent2D, GKGraph)
- **UI**: UIKit with custom overlays
- **Shaders**: Metal Shading Language
- **Build System**: Make + xcodebuild

## 📁 Project Structure

```
MiniCity/
├── Makefile                 # Build system and workflows
├── MiniCity/
│   ├── Engine/             # Metal rendering engine
│   │   ├── MetalEngine.swift
│   │   ├── Shaders.metal
│   │   └── CityGameController.swift
│   ├── Simulation/         # Game logic
│   │   └── GameplayKitTrafficSimulation.swift
│   ├── UI/                 # User interface
│   │   └── HUDOverlay.swift
│   └── Assets/             # Resources
├── scripts/                # Helper scripts
│   ├── check-dependencies.sh
│   ├── monitor-performance.sh
│   └── test-city-features.sh
└── docs/                   # Documentation
```

## 🎯 Key Features Implementation

### Traffic Simulation

Using GameplayKit's agent system for realistic traffic:
- GKAgent2D vehicles with mass and acceleration
- Path following through GKGraph road network
- Traffic light compliance
- Collision avoidance behaviors

### Rendering Pipeline

Metal-based rendering with:
- Instanced rendering for buildings
- Compute shaders for simulations
- PBR materials and lighting
- Depth buffer optimization
- Custom vertex/fragment shaders

### Camera System

Google Maps-style controls:
- Pan, zoom, rotate, tilt
- Momentum-based scrolling
- Boundary constraints
- Keyboard shortcuts (Q/E for rotation)

## 🛠️ Development

### Configuration Files

- `.swiftlint.yml` - Code style enforcement
- `ExportOptions.plist` - App export settings
- `Makefile.local` - Personal overrides (create your own)

### Debugging

```bash
make logs           # Stream app logs
make crash-logs     # View crash logs
make debug          # Debug build
make screenshot     # Capture screenshot
make record         # Record video
```

### Performance Monitoring

```bash
# Real-time monitoring
./scripts/monitor-performance.sh --continuous

# Generate reports
make report-performance
make report-size
```

## 🔗 Resources

### Metal Framework Documentation

```bash
make links          # Display all Metal documentation links
make metal-specs    # Metal Shading Language Specification
make xcode-config   # Xcode CLI configuration guide
```

### Key Documentation

- [Metal Programming Guide](https://developer.apple.com/documentation/metal)
- [GameplayKit Guide](https://developer.apple.com/documentation/gameplaykit)
- [Metal Best Practices](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/)

## 📊 Project Statistics

```bash
make city-stats     # Show current statistics
```

Current stats:
- Buildings types: 5 (residential, commercial, industrial, office, service)
- Vehicle types: 4 (car, bus, truck, emergency)
- Shaders: 10+ (terrain, building, road, water, particles)
- Performance: 60 FPS with 200+ vehicles

## 🚦 Roadmap

- [ ] Particle effects for smoke and weather
- [ ] Day/night cycle with dynamic lighting
- [ ] Economic simulation system
- [ ] Zoning and district management
- [ ] Public transport networks
- [ ] Procedural building generation
- [ ] Save/load city functionality
- [ ] Multiplayer support

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Run `make validate` before committing
4. Submit a pull request

### Development Guidelines

- Use `make check` before commits
- Follow SwiftLint rules
- Add tests for new features
- Update documentation
- Use the Makefile for all operations

## 📝 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Inspired by SimCity 4 and Cities: Skylines
- Built with Apple's Metal and GameplayKit frameworks
- Uses modern iOS development best practices

---

**Pro Tip**: Run `make help` anytime to see all available commands!