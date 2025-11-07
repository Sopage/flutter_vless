#!/bin/bash

# Download script for Xray-core binary for macOS
# Downloads the latest Xray-core v25.10.15+ from official releases

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/build/xray-macos-bin"
MIN_VERSION="25.10.15"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Xray-core Downloader for macOS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    XRAY_ARCH="arm64"
    # Try different possible file names
    XRAY_FILE_OPTIONS=("Xray-macos-arm64-v8a.zip" "Xray-macos-arm64.zip" "xray-macos-arm64-v8a.zip")
elif [ "$ARCH" = "x86_64" ]; then
    XRAY_ARCH="64"
    XRAY_FILE_OPTIONS=("Xray-macos-64.zip" "xray-macos-64.zip")
else
    echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
    exit 1
fi

echo -e "${GREEN}Detected architecture: $ARCH${NC}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Get latest release info
echo -e "${GREEN}Fetching latest Xray-core release information...${NC}"
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE" ]; then
    echo -e "${RED}Error: Failed to fetch release information${NC}"
    exit 1
fi

echo -e "${GREEN}Latest release: $LATEST_RELEASE${NC}"

# Extract version number
VERSION_NUMBER=$(echo "$LATEST_RELEASE" | sed 's/v//')
echo -e "${GREEN}Version: $VERSION_NUMBER${NC}"

# Check if version meets minimum requirement
if [ "$(printf '%s\n' "$MIN_VERSION" "$VERSION_NUMBER" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
    echo -e "${YELLOW}Warning: Version $VERSION_NUMBER is older than required $MIN_VERSION${NC}"
    echo -e "${YELLOW}Continuing anyway...${NC}"
fi

# Find correct download URL by checking assets
echo -e "${GREEN}Finding correct asset file...${NC}"
ASSETS_JSON=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest")

# Try to find macOS asset
DOWNLOAD_URL=""
for FILE_NAME in "${XRAY_FILE_OPTIONS[@]}"; do
    # Check if file exists in release
    if echo "$ASSETS_JSON" | grep -q "\"name\":\"$FILE_NAME\""; then
        DOWNLOAD_URL=$(echo "$ASSETS_JSON" | grep -A 1 "\"name\":\"$FILE_NAME\"" | grep "browser_download_url" | sed -E 's/.*"browser_download_url":\s*"([^"]+)".*/\1/')
        if [ -n "$DOWNLOAD_URL" ]; then
            echo -e "${GREEN}Found asset: $FILE_NAME${NC}"
            break
        fi
    fi
done

# If not found, try direct URL with first option
if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${YELLOW}Trying direct download URL...${NC}"
    for FILE_NAME in "${XRAY_FILE_OPTIONS[@]}"; do
        TEST_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_RELEASE}/${FILE_NAME}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --head "$TEST_URL")
        if [ "$HTTP_CODE" = "200" ]; then
            DOWNLOAD_URL="$TEST_URL"
            echo -e "${GREEN}Found: $FILE_NAME${NC}"
            break
        fi
    done
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Error: Could not find Xray binary for macOS $ARCH${NC}"
    echo -e "${YELLOW}Available assets in latest release:${NC}"
    echo "$ASSETS_JSON" | grep '"name":' | head -10
    echo ""
    echo -e "${YELLOW}Please download manually from: https://github.com/XTLS/Xray-core/releases${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Downloading Xray-core...${NC}"
echo -e "${BLUE}URL: $DOWNLOAD_URL${NC}"
echo ""

# Download
curl -L -o "${OUTPUT_DIR}/xray.zip" "$DOWNLOAD_URL" || {
    echo -e "${RED}Error: Failed to download Xray-core${NC}"
    exit 1
}

# Extract
echo -e "${GREEN}Extracting...${NC}"
cd "${OUTPUT_DIR}"
unzip -q xray.zip || {
    echo -e "${RED}Error: Failed to extract archive${NC}"
    exit 1
}

# Find xray binary
XRAY_BINARY=""
if [ -f "xray" ]; then
    XRAY_BINARY="xray"
elif [ -f "Xray" ]; then
    XRAY_BINARY="Xray"
else
    echo -e "${RED}Error: Xray binary not found in archive${NC}"
    exit 1
fi

# Make executable
chmod +x "$XRAY_BINARY"

# Verify
if [ -f "$XRAY_BINARY" ] && [ -x "$XRAY_BINARY" ]; then
    echo -e "${GREEN}✓ Xray binary extracted and made executable${NC}"
    
    # Get version
    VERSION_OUTPUT=$("./$XRAY_BINARY" version 2>&1 || echo "")
    echo -e "${GREEN}Version info:${NC}"
    echo "$VERSION_OUTPUT" | head -3
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Download Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Xray binary location: ${OUTPUT_DIR}/${XRAY_BINARY}"
    echo ""
    echo "Next steps:"
    echo "1. Copy xray binary to your app bundle:"
    echo "   cp ${OUTPUT_DIR}/${XRAY_BINARY} example/macos/Runner/xray"
    echo ""
    echo "2. Or place it in Application Support:"
    echo "   mkdir -p ~/Library/Application\\ Support/flutter_vless"
    echo "   cp ${OUTPUT_DIR}/${XRAY_BINARY} ~/Library/Application\\ Support/flutter_vless/xray"
    echo ""
    echo "3. For Network Extension, place in shared container:"
    echo "   # Configure in Xcode: App Groups capability"
    echo "   # Then copy to shared container path"
else
    echo -e "${RED}Error: Failed to prepare Xray binary${NC}"
    exit 1
fi

# Clean up zip file
rm -f "${OUTPUT_DIR}/xray.zip"

