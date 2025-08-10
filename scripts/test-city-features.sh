#!/bin/bash
# Automated testing for MiniCity features

set -e

PROJECT="MiniCity.xcodeproj"
SCHEME="MiniCity"
DEVICE="iPhone 15 Pro"
OS="17.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== MiniCity Feature Tests ===${NC}\n"

# Test categories
TEST_RESULTS=()

# Function to run a test
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -e "${YELLOW}Testing: $test_name${NC}"
    
    if eval "$test_command" &> /dev/null; then
        echo -e "${GREEN}  ✓ Passed${NC}"
        TEST_RESULTS+=("$test_name: PASS")
        return 0
    else
        echo -e "${RED}  ✗ Failed${NC}"
        TEST_RESULTS+=("$test_name: FAIL")
        return 1
    fi
}

# Test Metal rendering pipeline
test_metal_rendering() {
    run_test "Metal Pipeline" \
        "xcodebuild -project $PROJECT -scheme $SCHEME \
         -destination 'platform=iOS Simulator,name=$DEVICE,OS=$OS' \
         -only-testing:MiniCityTests/MetalEngineTests \
         test-without-building"
}

# Test GameplayKit traffic simulation
test_traffic_simulation() {
    run_test "Traffic Simulation" \
        "xcodebuild -project $PROJECT -scheme $SCHEME \
         -destination 'platform=iOS Simulator,name=$DEVICE,OS=$OS' \
         -only-testing:MiniCityTests/TrafficSimulationTests \
         test-without-building"
}

# Test camera controls
test_camera_controls() {
    run_test "Camera Controls" \
        "xcodebuild -project $PROJECT -scheme $SCHEME \
         -destination 'platform=iOS Simulator,name=$DEVICE,OS=$OS' \
         -only-testing:MiniCityTests/CameraControllerTests \
         test-without-building"
}

# Test HUD overlay
test_hud_overlay() {
    run_test "HUD Overlay" \
        "xcodebuild -project $PROJECT -scheme $SCHEME \
         -destination 'platform=iOS Simulator,name=$DEVICE,OS=$OS' \
         -only-testing:MiniCityTests/HUDOverlayTests \
         test-without-building"
}

# Test city grid system
test_city_grid() {
    run_test "City Grid" \
        "xcodebuild -project $PROJECT -scheme $SCHEME \
         -destination 'platform=iOS Simulator,name=$DEVICE,OS=$OS' \
         -only-testing:MiniCityTests/CityGridTests \
         test-without-building"
}

# Performance benchmarks
run_performance_tests() {
    echo -e "\n${CYAN}Performance Benchmarks:${NC}"
    
    # Frame rate test
    echo -e "${YELLOW}Frame Rate Test...${NC}"
    xcodebuild -project $PROJECT -scheme $SCHEME \
        -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS" \
        -only-testing:MiniCityTests/PerformanceTests/testFrameRate \
        test 2>&1 | grep -E "(measured|fps)" | tail -5
    
    # Memory test
    echo -e "${YELLOW}Memory Usage Test...${NC}"
    xcodebuild -project $PROJECT -scheme $SCHEME \
        -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS" \
        -only-testing:MiniCityTests/PerformanceTests/testMemoryUsage \
        test 2>&1 | grep -E "(memory|MB)" | tail -5
    
    # Traffic simulation performance
    echo -e "${YELLOW}Traffic Simulation Performance...${NC}"
    xcodebuild -project $PROJECT -scheme $SCHEME \
        -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS" \
        -only-testing:MiniCityTests/PerformanceTests/testTrafficPerformance \
        test 2>&1 | grep -E "(vehicles|fps)" | tail -5
}

# UI automation tests
run_ui_tests() {
    echo -e "\n${CYAN}UI Automation Tests:${NC}"
    
    local ui_tests=(
        "testBuildingPlacement"
        "testCameraGestures"
        "testHUDInteraction"
        "testSimulationToggle"
    )
    
    for test in "${ui_tests[@]}"; do
        run_test "UI: $test" \
            "xcodebuild -project $PROJECT -scheme $SCHEME \
             -destination 'platform=iOS Simulator,name=$DEVICE,OS=$OS' \
             -only-testing:MiniCityUITests/$test \
             test-without-building"
    done
}

# Shader validation
validate_shaders() {
    echo -e "\n${CYAN}Shader Validation:${NC}"
    
    SHADER_FILES=$(find . -name "*.metal" -type f)
    SHADER_COUNT=0
    SHADER_ERRORS=0
    
    for shader in $SHADER_FILES; do
        SHADER_COUNT=$((SHADER_COUNT + 1))
        echo -e "${YELLOW}Validating: $(basename $shader)${NC}"
        
        if xcrun -sdk iphonesimulator metal -c "$shader" -o /tmp/test.air 2>/dev/null; then
            echo -e "${GREEN}  ✓ Valid${NC}"
        else
            echo -e "${RED}  ✗ Invalid${NC}"
            SHADER_ERRORS=$((SHADER_ERRORS + 1))
        fi
    done
    
    echo -e "\nShader Summary: $((SHADER_COUNT - SHADER_ERRORS))/$SHADER_COUNT valid"
}

# Asset validation
validate_assets() {
    echo -e "\n${CYAN}Asset Validation:${NC}"
    
    # Check textures
    TEXTURE_COUNT=$(find MiniCity/Assets -name "*.png" -o -name "*.jpg" | wc -l)
    echo "  Textures: $TEXTURE_COUNT files"
    
    # Check models
    MODEL_COUNT=$(find MiniCity/Assets -name "*.obj" -o -name "*.usdz" | wc -l)
    echo "  3D Models: $MODEL_COUNT files"
    
    # Check sounds
    SOUND_COUNT=$(find MiniCity/Assets -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" | wc -l)
    echo "  Sounds: $SOUND_COUNT files"
    
    # Check for missing assets
    echo -e "${YELLOW}Checking for missing assets...${NC}"
    MISSING=$(grep -r "Assets/" MiniCity --include="*.swift" | grep -v "//" | cut -d'"' -f2 | sort -u | while read asset; do
        if [ ! -f "MiniCity/$asset" ]; then
            echo "  Missing: $asset"
        fi
    done)
    
    if [ -z "$MISSING" ]; then
        echo -e "${GREEN}  ✓ All referenced assets found${NC}"
    else
        echo -e "${RED}$MISSING${NC}"
    fi
}

# Integration test
run_integration_test() {
    echo -e "\n${CYAN}Integration Test:${NC}"
    echo "Starting full city simulation..."
    
    # Launch app
    xcrun simctl launch booted com.drunkonjava.MiniCity
    sleep 5
    
    # Take screenshot
    xcrun simctl io booted screenshot /tmp/minicity_test.png
    echo "  Screenshot captured"
    
    # Check if app is running
    if xcrun simctl spawn booted launchctl list | grep -q "com.drunkonjava.MiniCity"; then
        echo -e "${GREEN}  ✓ App running successfully${NC}"
        
        # Get memory usage
        PID=$(xcrun simctl spawn booted launchctl list | grep "com.drunkonjava.MiniCity" | awk '{print $1}')
        if [ ! -z "$PID" ]; then
            MEMORY=$(xcrun simctl spawn booted vmmap $PID 2>/dev/null | grep "TOTAL" | tail -1 | awk '{print $3}')
            echo "  Memory usage: $MEMORY"
        fi
    else
        echo -e "${RED}  ✗ App not running${NC}"
    fi
    
    # Terminate app
    xcrun simctl terminate booted com.drunkonjava.MiniCity
}

# Generate test report
generate_report() {
    echo -e "\n${CYAN}=== Test Report ===${NC}"
    echo "Date: $(date)"
    echo "Device: $DEVICE ($OS)"
    echo ""
    echo "Test Results:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ $result == *"PASS"* ]]; then
            echo -e "  ${GREEN}$result${NC}"
        else
            echo -e "  ${RED}$result${NC}"
        fi
    done
    
    # Save to file
    REPORT_FILE="reports/test_report_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p reports
    {
        echo "MiniCity Test Report"
        echo "===================="
        echo "Date: $(date)"
        echo "Device: $DEVICE ($OS)"
        echo ""
        printf '%s\n' "${TEST_RESULTS[@]}"
    } > "$REPORT_FILE"
    
    echo -e "\n${GREEN}Report saved to: $REPORT_FILE${NC}"
}

# Main execution
case "${1:-all}" in
    metal)
        test_metal_rendering
        ;;
    traffic)
        test_traffic_simulation
        ;;
    camera)
        test_camera_controls
        ;;
    hud)
        test_hud_overlay
        ;;
    grid)
        test_city_grid
        ;;
    performance)
        run_performance_tests
        ;;
    ui)
        run_ui_tests
        ;;
    shaders)
        validate_shaders
        ;;
    assets)
        validate_assets
        ;;
    integration)
        run_integration_test
        ;;
    all)
        test_metal_rendering
        test_traffic_simulation
        test_camera_controls
        test_hud_overlay
        test_city_grid
        validate_shaders
        validate_assets
        run_performance_tests
        run_ui_tests
        run_integration_test
        generate_report
        ;;
    *)
        echo "Usage: $0 [all|metal|traffic|camera|hud|grid|performance|ui|shaders|assets|integration]"
        exit 1
        ;;
esac