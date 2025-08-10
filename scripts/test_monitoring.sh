#!/bin/bash

# Test script for Claude Code monitoring system
# ==============================================

set -euo pipefail

PROJECT_DIR="/Users/griffin/Projects/MiniCity/MiniCity"
MONITOR_DIR="/tmp/minicity_monitor"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Claude Code Monitoring System Test ===${NC}"
echo ""

# Test 1: Check scripts exist
echo -e "${YELLOW}Test 1: Checking script files...${NC}"
if [[ -f "$PROJECT_DIR/scripts/claude_runner.sh" ]] && \
   [[ -f "$PROJECT_DIR/scripts/monitoring/crash_monitor.sh" ]] && \
   [[ -f "$PROJECT_DIR/scripts/monitoring/claude_diagnostic.sh" ]]; then
    echo -e "${GREEN}✓ All scripts present${NC}"
else
    echo -e "${RED}✗ Missing scripts${NC}"
    exit 1
fi

# Test 2: Check executability
echo -e "${YELLOW}Test 2: Checking script permissions...${NC}"
if [[ -x "$PROJECT_DIR/scripts/claude_runner.sh" ]] && \
   [[ -x "$PROJECT_DIR/scripts/monitoring/crash_monitor.sh" ]] && \
   [[ -x "$PROJECT_DIR/scripts/monitoring/claude_diagnostic.sh" ]]; then
    echo -e "${GREEN}✓ Scripts are executable${NC}"
else
    echo -e "${RED}✗ Scripts not executable${NC}"
    echo "Run: chmod +x $PROJECT_DIR/scripts/*.sh $PROJECT_DIR/scripts/monitoring/*.sh"
    exit 1
fi

# Test 3: Check Makefile targets
echo -e "${YELLOW}Test 3: Checking Makefile targets...${NC}"
cd "$PROJECT_DIR"
if make -n claude-run > /dev/null 2>&1 && \
   make -n claude-diagnose > /dev/null 2>&1 && \
   make -n claude-status > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Makefile targets configured${NC}"
else
    echo -e "${RED}✗ Makefile targets missing${NC}"
    exit 1
fi

# Test 4: Test diagnostic script
echo -e "${YELLOW}Test 4: Testing diagnostic script...${NC}"
"$PROJECT_DIR/scripts/monitoring/claude_diagnostic.sh" status > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Diagnostic script works${NC}"
else
    echo -e "${RED}✗ Diagnostic script failed${NC}"
    exit 1
fi

# Test 5: Check dependencies
echo -e "${YELLOW}Test 5: Checking dependencies...${NC}"
missing_deps=()
command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
command -v xcrun >/dev/null 2>&1 || missing_deps+=("xcrun")
command -v xcodebuild >/dev/null 2>&1 || missing_deps+=("xcodebuild")

if [[ ${#missing_deps[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All dependencies installed${NC}"
else
    echo -e "${RED}✗ Missing dependencies: ${missing_deps[*]}${NC}"
    echo "Install with: brew install ${missing_deps[*]}"
    exit 1
fi

# Test 6: Test monitoring directory creation
echo -e "${YELLOW}Test 6: Testing monitoring directory...${NC}"
mkdir -p "$MONITOR_DIR"
if [[ -d "$MONITOR_DIR" ]]; then
    echo -e "${GREEN}✓ Monitoring directory accessible${NC}"
else
    echo -e "${RED}✗ Cannot create monitoring directory${NC}"
    exit 1
fi

# Test 7: Test simulator detection
echo -e "${YELLOW}Test 7: Checking simulator availability...${NC}"
device_id=$(xcrun simctl list devices | grep "iPhone 16 Pro Max" | grep -E -o "\([A-F0-9\-]+\)" | tr -d '()' | head -1)
if [[ -n "$device_id" ]]; then
    echo -e "${GREEN}✓ Simulator device found: $device_id${NC}"
else
    echo -e "${YELLOW}⚠ No iPhone 16 Pro Max simulator found${NC}"
    echo "This is not critical but may affect monitoring"
fi

# Test 8: Quick diagnostic test
echo -e "${YELLOW}Test 8: Running quick diagnostic...${NC}"
diagnostic_output=$("$PROJECT_DIR/scripts/monitoring/claude_diagnostic.sh" status 2>/dev/null)
if echo "$diagnostic_output" | jq -e '.status' > /dev/null 2>&1; then
    status=$(echo "$diagnostic_output" | jq -r '.status')
    echo -e "${GREEN}✓ Diagnostic output valid (status: $status)${NC}"
else
    echo -e "${YELLOW}⚠ Diagnostic output may need initialization${NC}"
fi

echo ""
echo -e "${GREEN}=== All Tests Passed ===${NC}"
echo ""
echo -e "${BLUE}System is ready for Claude Code monitoring!${NC}"
echo ""
echo "Usage:"
echo "  make claude-run      # Run with monitoring"
echo "  make claude-diagnose # Get diagnostics"
echo "  make claude-status   # Check status"
echo ""
echo "For Claude Code CLI, use:"
echo "  cd $PROJECT_DIR && make claude-run"
echo ""
