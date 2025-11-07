#!/bin/bash

# Build script for XRay framework for macOS
# This script builds XRay framework using gomobile bind for macOS
# Requires: Go 1.21+, gomobile, and XRay dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
XRAY_MOBILE_REPO="github.com/EbrahimTahernejad/xray-mobile"
XRAY_VERSION="v25.10.15"
OUTPUT_DIR="$(pwd)/build/xray-macos"
FRAMEWORK_NAME="XRay"
MIN_MACOS_VERSION="11.0"

echo -e "${GREEN}Building XRay framework for macOS${NC}"
echo "Version: ${XRAY_VERSION}"
echo "Output: ${OUTPUT_DIR}"
echo ""

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed. Please install Go 1.21 or later.${NC}"
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
REQUIRED_VERSION="1.21"
if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo -e "${RED}Error: Go version $GO_VERSION is too old. Please install Go $REQUIRED_VERSION or later.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Go version: $(go version)${NC}"

# Check if gomobile is installed
GOMOBILE_CMD=""
if command -v gomobile &> /dev/null; then
    GOMOBILE_CMD="gomobile"
else
    # Try to find gomobile in GOPATH/bin
    if [ -n "$GOPATH" ] && [ -f "$GOPATH/bin/gomobile" ]; then
        GOMOBILE_CMD="$GOPATH/bin/gomobile"
        export PATH="$GOPATH/bin:$PATH"
    elif [ -f "$HOME/go/bin/gomobile" ]; then
        GOMOBILE_CMD="$HOME/go/bin/gomobile"
        export PATH="$HOME/go/bin:$PATH"
    else
        echo -e "${YELLOW}gomobile not found. Installing...${NC}"
        go install golang.org/x/mobile/cmd/gomobile@latest
        
        # Find gomobile after installation
        if [ -n "$GOPATH" ] && [ -f "$GOPATH/bin/gomobile" ]; then
            GOMOBILE_CMD="$GOPATH/bin/gomobile"
            export PATH="$GOPATH/bin:$PATH"
        elif [ -f "$HOME/go/bin/gomobile" ]; then
            GOMOBILE_CMD="$HOME/go/bin/gomobile"
            export PATH="$HOME/go/bin:$PATH"
        else
            # Try to get GOPATH from go env
            GO_BIN_PATH=$(go env GOPATH)/bin
            if [ -f "$GO_BIN_PATH/gomobile" ]; then
                GOMOBILE_CMD="$GO_BIN_PATH/gomobile"
                export PATH="$GO_BIN_PATH:$PATH"
            else
                echo -e "${RED}Error: Failed to find gomobile after installation${NC}"
                echo "Please ensure GOPATH/bin is in your PATH or run: export PATH=\$(go env GOPATH)/bin:\$PATH"
                exit 1
            fi
        fi
    fi
fi

# Initialize gomobile if needed
GOMOBILE_DIR="$HOME/gomobile"
if [ -n "$GOPATH" ]; then
    GOMOBILE_DIR="$GOPATH/gomobile"
fi

if [ ! -d "$GOMOBILE_DIR" ]; then
    echo -e "${YELLOW}Initializing gomobile...${NC}"
    "$GOMOBILE_CMD" init || {
        echo -e "${YELLOW}gomobile init failed, trying with explicit path...${NC}"
        GOMOBILE_DIR="$(go env GOPATH)/gomobile"
        mkdir -p "$GOMOBILE_DIR"
        export GOMOBILE="$GOMOBILE_DIR"
        "$GOMOBILE_CMD" init
    }
fi

# Ensure gomobile dependencies are available by downloading the mobile package
echo -e "${YELLOW}Ensuring gomobile dependencies are available...${NC}"
TEMP_DEPS_DIR=$(mktemp -d)
cd "$TEMP_DEPS_DIR"
go mod init temp-deps 2>/dev/null || true
go get golang.org/x/mobile@latest || true
cd - > /dev/null
rm -rf "$TEMP_DEPS_DIR"

echo -e "${GREEN}✓ gomobile is installed at: $GOMOBILE_CMD${NC}"

# Check if Xcode is installed (required for macOS framework building)
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: Xcode command line tools are required for building macOS frameworks${NC}"
    echo "Please install Xcode command line tools: xcode-select --install"
    exit 1
fi

# Verify Xcode is properly configured
if ! xcodebuild -version &> /dev/null; then
    echo -e "${RED}Error: Xcode is not properly configured${NC}"
    echo "Please run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -n1)
echo -e "${GREEN}✓ Xcode found: $XCODE_VERSION${NC}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Set up Go environment for macOS
export GOOS=darwin
export CGO_ENABLED=1

# Create a temporary Go module for building
TEMP_MODULE_DIR="${OUTPUT_DIR}/temp-module"
mkdir -p "${TEMP_MODULE_DIR}"
cd "${TEMP_MODULE_DIR}"

# Initialize Go module
go mod init temp-xray-build 2>/dev/null || true

# Build for macOS arm64 (Apple Silicon)
echo -e "${GREEN}Building for macOS arm64...${NC}"
export GOARCH=arm64
cd "${TEMP_MODULE_DIR}"
"$GOMOBILE_CMD" bind -target=macos/arm64 -o "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework" \
    -ldflags="-s -w" \
    "${XRAY_MOBILE_REPO}" || {
    echo -e "${RED}Error: Failed to build arm64 framework${NC}"
    echo "This might be due to:"
    echo "1. Network issues downloading dependencies"
    echo "2. Missing Go dependencies"
    echo "3. Xcode configuration issues"
    echo ""
    echo "Trying to download dependencies first..."
    go get "${XRAY_MOBILE_REPO}" || true
    "$GOMOBILE_CMD" bind -target=macos/arm64 -o "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework" \
        -ldflags="-s -w" \
        "${XRAY_MOBILE_REPO}"
}

# Build for macOS x86_64 (Intel) - only if on Intel Mac or with Rosetta
if [ "$(uname -m)" = "x86_64" ] || command -v arch &> /dev/null; then
    echo -e "${GREEN}Building for macOS x86_64...${NC}"
    export GOARCH=amd64
    cd "${TEMP_MODULE_DIR}"
    # Try building x86_64 using arch command if on Apple Silicon
    if [ "$(uname -m)" = "arm64" ]; then
        echo -e "${YELLOW}Building x86_64 on Apple Silicon (this may take longer)...${NC}"
        arch -x86_64 "$GOMOBILE_CMD" bind -target=macos/amd64 -o "${OUTPUT_DIR}/${FRAMEWORK_NAME}-x86_64.xcframework" \
            -ldflags="-s -w" \
            "${XRAY_MOBILE_REPO}" || {
            echo -e "${YELLOW}Warning: x86_64 build failed. Universal framework will only contain arm64.${NC}"
            echo -e "${YELLOW}To build x86_64, you may need Rosetta 2 installed.${NC}"
        }
    else
        "$GOMOBILE_CMD" bind -target=macos/amd64 -o "${OUTPUT_DIR}/${FRAMEWORK_NAME}-x86_64.xcframework" \
            -ldflags="-s -w" \
            "${XRAY_MOBILE_REPO}"
    fi
else
    echo -e "${YELLOW}Skipping x86_64 build (Apple Silicon Mac)${NC}"
    echo -e "${YELLOW}Note: Universal framework will only contain arm64${NC}"
fi

# Return to original directory
cd "${SCRIPT_DIR}/.."

# Create universal xcframework
echo -e "${GREEN}Creating universal XCFramework...${NC}"
UNIVERSAL_XCFRAMEWORK="${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

# Build xcodebuild command
XCBUILD_CMD="xcodebuild -create-xcframework"

# Add arm64 slice
if [ -d "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework" ]; then
    # Extract framework from xcframework
    ARM64_FRAMEWORK=$(find "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework" -name "*.framework" -type d | head -1)
    if [ -n "$ARM64_FRAMEWORK" ]; then
        XCBUILD_CMD="${XCBUILD_CMD} -framework \"${ARM64_FRAMEWORK}\""
    fi
fi

# Add x86_64 slice if it exists
if [ -d "${OUTPUT_DIR}/${FRAMEWORK_NAME}-x86_64.xcframework" ]; then
    X86_64_FRAMEWORK=$(find "${OUTPUT_DIR}/${FRAMEWORK_NAME}-x86_64.xcframework" -name "*.framework" -type d | head -1)
    if [ -n "$X86_64_FRAMEWORK" ]; then
        XCBUILD_CMD="${XCBUILD_CMD} -framework \"${X86_64_FRAMEWORK}\""
    fi
fi

XCBUILD_CMD="${XCBUILD_CMD} -output \"${UNIVERSAL_XCFRAMEWORK}\""

# Execute xcodebuild
eval "${XCBUILD_CMD}"

# If xcframework creation failed, try creating a simple framework from arm64
if [ ! -d "${UNIVERSAL_XCFRAMEWORK}" ] && [ -d "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework" ]; then
    echo -e "${YELLOW}Creating simple framework from arm64 xcframework...${NC}"
    UNIVERSAL_FRAMEWORK="${OUTPUT_DIR}/${FRAMEWORK_NAME}.framework"
    ARM64_FRAMEWORK=$(find "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework" -name "*.framework" -type d | head -1)
    if [ -n "$ARM64_FRAMEWORK" ]; then
        cp -R "${ARM64_FRAMEWORK}" "${UNIVERSAL_FRAMEWORK}"
        echo -e "${GREEN}✓ Framework created (arm64 only)${NC}"
    fi
fi

# Clean up individual architecture xcframeworks and temp module
rm -rf "${OUTPUT_DIR}/${FRAMEWORK_NAME}-arm64.xcframework"
rm -rf "${OUTPUT_DIR}/${FRAMEWORK_NAME}-x86_64.xcframework"
rm -rf "${TEMP_MODULE_DIR}"

echo ""
if [ -d "${UNIVERSAL_XCFRAMEWORK}" ]; then
    echo -e "${GREEN}✓ Build complete!${NC}"
    echo -e "${GREEN}XCFramework location: ${UNIVERSAL_XCFRAMEWORK}${NC}"
    echo ""
    echo "XCFramework slices:"
    ls -la "${UNIVERSAL_XCFRAMEWORK}/"
elif [ -d "${OUTPUT_DIR}/${FRAMEWORK_NAME}.framework" ]; then
    echo -e "${GREEN}✓ Build complete!${NC}"
    echo -e "${GREEN}Framework location: ${OUTPUT_DIR}/${FRAMEWORK_NAME}.framework${NC}"
else
    echo -e "${RED}Error: Failed to create framework${NC}"
    exit 1
fi
echo ""
echo "Next steps:"
echo "1. Use this framework to create a universal xcframework with iOS version"
echo "2. Run: ./scripts/create_universal_xcframework.sh"
echo ""
echo "If you encountered build errors, see: ./scripts/SETUP_GOMOBILE.md"

