# XRay Framework Build Scripts

This directory contains scripts for building XRay framework for macOS and creating universal XCFrameworks that support both iOS and macOS.

## Prerequisites

- **Go 1.21 or later**: Required for building XRay framework
- **gomobile**: Go mobile tool for building iOS/macOS frameworks
- **Xcode**: Required for creating XCFrameworks
- **macOS 11.0+**: Required for building macOS frameworks

## Quick Start

### Option 1: Build Everything Automatically

Run the all-in-one script:

```bash
./scripts/build_all.sh
```

This will:
1. Build XRay framework for macOS (arm64 + x86_64)
2. Create a universal XCFramework with iOS and macOS slices
3. Copy the result to both `example/ios/` and `example/macos/` directories

### Option 2: Step-by-Step Build

#### Step 1: Build macOS Framework

```bash
./scripts/build_xray_macos.sh
```

This creates a universal macOS framework at `build/xray-macos/XRay.framework` supporting both arm64 (Apple Silicon) and x86_64 (Intel).

#### Step 2: Create Universal XCFramework

```bash
./scripts/create_universal_xcframework.sh
```

This combines the existing iOS XRay.xcframework with the newly built macOS framework into a universal XCFramework at `build/XRay-universal.xcframework`.

#### Step 3: Install the Framework

```bash
# Copy to iOS example
cp -R build/XRay-universal.xcframework example/ios/XRay.xcframework

# Copy to macOS example
cp -R build/XRay-universal.xcframework example/macos/XRay.xcframework
```

## Scripts Overview

### `build_xray_macos.sh`

Builds XRay framework for macOS using gomobile bind.

**What it does:**
- Checks Go and gomobile installation
- Builds framework for macOS arm64 (Apple Silicon)
- Builds framework for macOS x86_64 (Intel)
- Creates a universal framework using `lipo`
- Outputs to `build/xray-macos/XRay.framework`

**Requirements:**
- Go 1.21+
- gomobile (installed automatically if missing)
- XRay mobile package: `github.com/EbrahimTahernejad/xray-mobile`

### `create_universal_xcframework.sh`

Creates a universal XCFramework containing both iOS and macOS slices.

**What it does:**
- Extracts slices from existing iOS XRay.xcframework
- Combines with macOS framework
- Creates universal XCFramework using `xcodebuild`
- Outputs to `build/XRay-universal.xcframework`

**Requirements:**
- Existing iOS XRay.xcframework in `example/ios/`
- macOS framework from `build_xray_macos.sh`
- Xcode command line tools

## XRay Version

The scripts are configured to use **XRay version 25.10.15 or later** (as specified in the xray-mobile package).

To verify the version after building:

```bash
# For macOS framework
otool -L build/xray-macos/XRay.framework/XRay | grep -i xray

# For iOS framework (requires iOS device/simulator)
# Check version programmatically using XRayGetVersion() API
```

## Troubleshooting

### Go/gomobile Issues

If gomobile is not found:
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

### Build Failures

1. **Check Go version**: Must be 1.21 or later
   ```bash
   go version
   ```

2. **Check network access**: Building requires downloading Go dependencies
   ```bash
   go env GOPROXY
   ```

3. **Clean build**: Remove build directory and try again
   ```bash
   rm -rf build/
   ./scripts/build_xray_macos.sh
   ```

### Framework Architecture Issues

Verify framework architectures:
```bash
# Check macOS framework
lipo -info build/xray-macos/XRay.framework/XRay

# Check XCFramework slices
xcodebuild -checkFirstLaunchStatus
```

### XCFramework Creation Issues

If xcodebuild fails:
1. Ensure Xcode command line tools are installed:
   ```bash
   xcode-select --install
   ```

2. Verify iOS xcframework exists:
   ```bash
   ls -la example/ios/XRay.xcframework/
   ```

## Modern Build Approach (2025)

These scripts use modern build practices:

- **Universal binaries**: Single framework supports multiple architectures
- **XCFramework format**: Apple's recommended format for multi-platform frameworks
- **Version pinning**: Explicit version requirements (25.10.15+)
- **Error handling**: Comprehensive error checking and user feedback
- **Automated dependency management**: Automatic gomobile installation
- **Clean separation**: Modular scripts for different build stages

## Integration with CI/CD

These scripts can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Build XRay Framework
  run: |
    ./scripts/build_xray_macos.sh
    ./scripts/create_universal_xcframework.sh
```

## Notes

- The macOS framework requires macOS 11.0+ as minimum deployment target
- The framework is built with CGO enabled for full functionality
- Universal frameworks are larger but provide better compatibility
- Always verify the framework works on both architectures before committing

