#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"

(
  cd "$EXAMPLE_DIR"
  flutter pub get
  flutter build ios --debug --no-codesign -t lib/main.dart
)

echo "Example iOS app mode restored: FLUTTER_TARGET=lib/main.dart"
