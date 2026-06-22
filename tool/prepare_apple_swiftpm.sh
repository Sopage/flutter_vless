#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="${EXAMPLE_DIR:-$ROOT_DIR/example}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
CLEAR_XCODE_DERIVED_DATA="${CLEAR_XCODE_DERIVED_DATA:-true}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter is not available in PATH" >&2
  exit 127
fi

patch_platform() {
  local manifest="$1"
  local platform="$2"
  local version="$3"

  if [[ ! -f "$manifest" ]]; then
    echo "Error: generated Swift package manifest not found: $manifest" >&2
    echo "Run this script from a checkout with the example app present." >&2
    exit 1
  fi

  /usr/bin/perl -0pi -e \
    "s/\\.$platform\\(\"[0-9]+(?:\\.[0-9]+){0,2}\"\\)/.$platform(\"$version\")/g" \
    "$manifest"

  if ! grep -q "\\.$platform(\"$version\")" "$manifest"; then
    echo "Error: failed to set .$platform(\"$version\") in $manifest" >&2
    exit 1
  fi
}

resolve_packages() {
  local project_dir="$1"
  local workspace="$2"
  local scheme="$3"

  if command -v xcodebuild >/dev/null 2>&1 && [[ -d "$project_dir" ]]; then
    (
      cd "$project_dir"
      xcodebuild \
        -resolvePackageDependencies \
        -workspace "$workspace" \
        -scheme "$scheme" \
        -skipPackageUpdates \
        -skipPackagePluginValidation \
        -skipPackageSignatureValidation >/dev/null
    )
  fi
}

clear_derived_data_for_xcode_container() {
  local xcode_container_path="$1"
  local derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"

  if [[ "$CLEAR_XCODE_DERIVED_DATA" != "true" || ! -d "$derived_data_root" ]]; then
    return 0
  fi

  while IFS= read -r -d '' info_plist; do
    local cached_workspace
    cached_workspace="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$info_plist" 2>/dev/null || true)"
    if [[ "$cached_workspace" == "$xcode_container_path" ]]; then
      local derived_data_dir
      derived_data_dir="$(dirname "$info_plist")"
      echo "Removing stale Xcode DerivedData: $derived_data_dir"
      rm -rf "$derived_data_dir"
    fi
  done < <(find "$derived_data_root" -mindepth 2 -maxdepth 2 -name info.plist -print0)
}

(
  cd "$EXAMPLE_DIR"
  flutter pub get
  flutter build macos --config-only
  flutter build ios --simulator --config-only
)

patch_platform \
  "$EXAMPLE_DIR/macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift" \
  "macOS" \
  "$MACOS_DEPLOYMENT_TARGET"

patch_platform \
  "$EXAMPLE_DIR/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift" \
  "iOS" \
  "$IOS_DEPLOYMENT_TARGET"

rm -rf "$EXAMPLE_DIR"/build/xcode-derived-*

clear_derived_data_for_xcode_container "$EXAMPLE_DIR/macos/Runner.xcworkspace"
clear_derived_data_for_xcode_container "$EXAMPLE_DIR/macos/Runner.xcodeproj"
clear_derived_data_for_xcode_container "$EXAMPLE_DIR/ios/Runner.xcworkspace"
clear_derived_data_for_xcode_container "$EXAMPLE_DIR/ios/Runner.xcodeproj"

resolve_packages "$EXAMPLE_DIR/macos" "Runner.xcworkspace" "Runner"
resolve_packages "$EXAMPLE_DIR/ios" "Runner.xcworkspace" "Runner"

cat <<EOF
Apple SwiftPM setup is ready:
  macOS FlutterGeneratedPluginSwiftPackage: $MACOS_DEPLOYMENT_TARGET
  iOS FlutterGeneratedPluginSwiftPackage:   $IOS_DEPLOYMENT_TARGET

If Xcode is already open and still shows the old minimum-platform error,
close Xcode and reopen the workspace so it reloads the package graph.
EOF
