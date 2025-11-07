#!/bin/bash

# All-in-one script to build XRay framework for macOS and create universal XCFramework
# This script automates the entire build process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}XRay Universal Framework Builder${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Build macOS framework
echo -e "${GREEN}[1/3] Building XRay framework for macOS...${NC}"
"${SCRIPT_DIR}/build_xray_macos.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to build macOS framework${NC}"
    exit 1
fi

echo ""

# Step 2: Create universal XCFramework
echo -e "${GREEN}[2/3] Creating universal XCFramework...${NC}"
"${SCRIPT_DIR}/create_universal_xcframework.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create universal XCFramework${NC}"
    exit 1
fi

echo ""

# Step 3: Install frameworks
echo -e "${GREEN}[3/3] Installing frameworks to example projects...${NC}"

UNIVERSAL_XCFRAMEWORK="${PROJECT_ROOT}/build/XRay-universal.xcframework"

if [ ! -d "${UNIVERSAL_XCFRAMEWORK}" ]; then
    echo -e "${RED}Error: Universal XCFramework not found${NC}"
    exit 1
fi

# Backup existing frameworks
if [ -d "${PROJECT_ROOT}/example/ios/XRay.xcframework" ]; then
    echo -e "${YELLOW}Backing up existing iOS framework...${NC}"
    mv "${PROJECT_ROOT}/example/ios/XRay.xcframework" \
       "${PROJECT_ROOT}/example/ios/XRay.xcframework.backup.$(date +%Y%m%d_%H%M%S)"
fi

if [ -d "${PROJECT_ROOT}/example/macos/XRay.xcframework" ]; then
    echo -e "${YELLOW}Backing up existing macOS framework...${NC}"
    mv "${PROJECT_ROOT}/example/macos/XRay.xcframework" \
       "${PROJECT_ROOT}/example/macos/XRay.xcframework.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Copy to iOS
echo -e "${GREEN}Copying to iOS example...${NC}"
cp -R "${UNIVERSAL_XCFRAMEWORK}" "${PROJECT_ROOT}/example/ios/XRay.xcframework"

# Copy to macOS
echo -e "${GREEN}Copying to macOS example...${NC}"
cp -R "${UNIVERSAL_XCFRAMEWORK}" "${PROJECT_ROOT}/example/macos/XRay.xcframework"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Universal XCFramework has been installed to:"
echo "  - example/ios/XRay.xcframework"
echo "  - example/macos/XRay.xcframework"
echo ""
echo "Next steps:"
echo "1. Open your Xcode project"
echo "2. Verify the framework is linked correctly"
echo "3. Build and run your app"
echo ""

