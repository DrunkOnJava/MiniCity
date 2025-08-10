#!/bin/bash
# Check and install required dependencies for MiniCity

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Checking MiniCity dependencies...${NC}"

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}✗ Xcode not found. Please install Xcode from the App Store.${NC}"
    exit 1
else
    XCODE_VERSION=$(xcodebuild -version | head -1 | cut -d' ' -f2)
    echo -e "${GREEN}✓ Xcode ${XCODE_VERSION}${NC}"
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo -e "${GREEN}✓ Homebrew$(NC)"
fi

# Check for SwiftLint
if ! command -v swiftlint &> /dev/null; then
    echo -e "${YELLOW}Installing SwiftLint...${NC}"
    brew install swiftlint
else
    echo -e "${GREEN}✓ SwiftLint$(NC)"
fi

# Check for SwiftFormat
if ! command -v swiftformat &> /dev/null; then
    echo -e "${YELLOW}Installing SwiftFormat...${NC}"
    brew install swiftformat
else
    echo -e "${GREEN}✓ SwiftFormat$(NC)"
fi

# Check for xcbeautify
if ! command -v xcbeautify &> /dev/null; then
    echo -e "${YELLOW}Installing xcbeautify...${NC}"
    brew install xcbeautify
else
    echo -e "${GREEN}✓ xcbeautify${NC}"
fi

# Check for Metal tools
if ! command -v metal &> /dev/null; then
    echo -e "${YELLOW}Metal compiler not found. Installing Xcode command line tools...${NC}"
    xcode-select --install
else
    echo -e "${GREEN}✓ Metal compiler${NC}"
fi

# Check for iOS Simulator
if ! xcrun simctl list devices | grep -q "iPhone"; then
    echo -e "${RED}✗ No iOS simulators found. Please download simulators in Xcode.${NC}"
    exit 1
else
    SIM_COUNT=$(xcrun simctl list devices | grep "iPhone" | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ iOS Simulators (${SIM_COUNT} devices)${NC}"
fi

# Check Ruby gems (for xcov)
if ! gem list -i xcov &> /dev/null; then
    echo -e "${YELLOW}Installing xcov...${NC}"
    sudo gem install xcov
else
    echo -e "${GREEN}✓ xcov${NC}"
fi

# Check for Git LFS (for large assets)
if ! command -v git-lfs &> /dev/null; then
    echo -e "${YELLOW}Installing Git LFS...${NC}"
    brew install git-lfs
    git lfs install
else
    echo -e "${GREEN}✓ Git LFS${NC}"
fi

echo -e "${GREEN}\n✓ All dependencies installed!${NC}"