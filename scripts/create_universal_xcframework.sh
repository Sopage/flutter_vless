#!/bin/bash

# Script to create a universal XCFramework containing both iOS and macOS slices
# This script combines existing iOS XRay.xcframework with newly built macOS framework

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IOS_XCFRAMEWORK="${PROJECT_ROOT}/example/ios/XRay.xcframework"
MACOS_FRAMEWORK="${PROJECT_ROOT}/build/xray-macos/XRay.framework"
OUTPUT_XCFRAMEWORK="${PROJECT_ROOT}/build/XRay-universal.xcframework"
TEMP_DIR="${PROJECT_ROOT}/build/xcframework-temp"

echo -e "${GREEN}Creating universal XCFramework for iOS and macOS${NC}"
echo ""

# Check if iOS xcframework exists
if [ ! -d "${IOS_XCFRAMEWORK}" ]; then
    echo -e "${RED}Error: iOS XCFramework not found at: ${IOS_XCFRAMEWORK}${NC}"
    echo "Please ensure the iOS XRay.xcframework exists in example/ios/"
    exit 1
fi

# Check if macOS framework exists
if [ ! -d "${MACOS_FRAMEWORK}" ]; then
    echo -e "${YELLOW}macOS framework not found. Building it first...${NC}"
    "${SCRIPT_DIR}/build_xray_macos.sh"
fi

if [ ! -d "${MACOS_FRAMEWORK}" ]; then
    echo -e "${RED}Error: macOS framework not found at: ${MACOS_FRAMEWORK}${NC}"
    echo "Please run: ./scripts/build_xray_macos.sh first"
    exit 1
fi

# Clean up temp directory
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"

# Extract iOS slices
echo -e "${GREEN}Extracting iOS slices...${NC}"
IOS_SLICES=()
for slice in "${IOS_XCFRAMEWORK}"/*/; do
    if [ -d "${slice}" ]; then
        slice_name=$(basename "${slice}")
        IOS_SLICES+=("-framework" "${slice}")
        echo "  - Found iOS slice: ${slice_name}"
    fi
done

# Prepare macOS framework for xcframework
echo -e "${GREEN}Preparing macOS framework...${NC}"
MACOS_SLICE_DIR="${TEMP_DIR}/macos"
mkdir -p "${MACOS_SLICE_DIR}"

# Determine macOS architectures
ARCHS=$(lipo -info "${MACOS_FRAMEWORK}/XRay" | grep -o "arm64\|x86_64" | tr '\n' ' ' || echo "arm64")
echo "  - macOS architectures: ${ARCHS}"

# Copy macOS framework
cp -R "${MACOS_FRAMEWORK}" "${MACOS_SLICE_DIR}/XRay.framework"

# Create xcframework
echo -e "${GREEN}Creating universal XCFramework...${NC}"

# Build xcodebuild command
XCBUILD_CMD="xcodebuild -create-xcframework"

# Add iOS slices
for slice in "${IOS_SLICES[@]}"; do
    XCBUILD_CMD="${XCBUILD_CMD} ${slice}"
done

# Add macOS slice
XCBUILD_CMD="${XCBUILD_CMD} -framework ${MACOS_SLICE_DIR}/XRay.framework"
XCBUILD_CMD="${XCBUILD_CMD} -output ${OUTPUT_XCFRAMEWORK}"

# Execute xcodebuild
eval "${XCBUILD_CMD}"

# Verify the created xcframework
if [ -d "${OUTPUT_XCFRAMEWORK}" ]; then
    echo ""
    echo -e "${GREEN}✓ Universal XCFramework created successfully!${NC}"
    echo -e "${GREEN}Location: ${OUTPUT_XCFRAMEWORK}${NC}"
    echo ""
    echo "XCFramework contents:"
    ls -la "${OUTPUT_XCFRAMEWORK}/"
    echo ""
    
    # Show Info.plist to verify slices
    if [ -f "${OUTPUT_XCFRAMEWORK}/Info.plist" ]; then
        echo "Available slices:"
        /usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "${OUTPUT_XCFRAMEWORK}/Info.plist" 2>/dev/null || \
        plutil -p "${OUTPUT_XCFRAMEWORK}/Info.plist" | grep -A 5 "LibraryIdentifier"
    fi
    
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Copy the universal xcframework to your project:"
    echo "   cp -R ${OUTPUT_XCFRAMEWORK} example/macos/XRay.xcframework"
    echo "   cp -R ${OUTPUT_XCFRAMEWORK} example/ios/XRay.xcframework"
    echo ""
    echo "2. Or update the existing xcframework:"
    echo "   rm -rf example/ios/XRay.xcframework"
    echo "   cp -R ${OUTPUT_XCFRAMEWORK} example/ios/XRay.xcframework"
    echo "   cp -R ${OUTPUT_XCFRAMEWORK} example/macos/XRay.xcframework"
else
    echo -e "${RED}Error: Failed to create XCFramework${NC}"
    exit 1
fi

# Clean up temp directory
rm -rf "${TEMP_DIR}"

