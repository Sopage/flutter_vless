#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/android_runtime/xray_android"
GRADLE_WRAPPER="${GRADLE_WRAPPER:-$ROOT_DIR/example/android/gradlew}"
XRAY_RUNTIME_VERSION="${XRAY_RUNTIME_VERSION:-26.6.1}"

"$GRADLE_WRAPPER" \
  -p "$PROJECT_DIR" \
  -PxrayRuntimeVersion="$XRAY_RUNTIME_VERSION" \
  clean verifyRuntimeInputs publishReleasePublicationToLocalBuildRepository

REPO_DIR="$PROJECT_DIR/build/repo"
AAR_PATH="$REPO_DIR/dev/tfox/fluttervless/xray-android/$XRAY_RUNTIME_VERSION/xray-android-$XRAY_RUNTIME_VERSION.aar"
BUNDLE_PATH="$PROJECT_DIR/build/xray-android-$XRAY_RUNTIME_VERSION-central-bundle.zip"

if [ ! -f "$AAR_PATH" ]; then
  echo "AAR was not created at $AAR_PATH" >&2
  exit 1
fi

for entry in \
  "jni/arm64-v8a/libxray.so" \
  "jni/arm64-v8a/libtun2socks.so" \
  "jni/armeabi-v7a/libxray.so" \
  "jni/armeabi-v7a/libtun2socks.so" \
  "assets/geoip.dat" \
  "assets/geosite.dat"; do
  if ! unzip -l "$AAR_PATH" "$entry" >/dev/null 2>&1; then
    echo "AAR is missing $entry" >&2
    exit 1
  fi
done

checksum_md5() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  else
    md5 -q "$1"
  fi
}

checksum_sha1() {
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$1" | awk '{print $1}'
  else
    shasum -a 1 "$1" | awk '{print $1}'
  fi
}

while IFS= read -r -d '' artifact; do
  checksum_md5 "$artifact" > "$artifact.md5"
  checksum_sha1 "$artifact" > "$artifact.sha1"
done < <(find "$REPO_DIR" -type f ! -name '*.md5' ! -name '*.sha1' -print0)

rm -f "$BUNDLE_PATH"
(cd "$REPO_DIR" && zip -qr "$BUNDLE_PATH" .)

echo "Android runtime AAR: $AAR_PATH"
echo "Local Maven repo: $REPO_DIR"
echo "Central bundle: $BUNDLE_PATH"
