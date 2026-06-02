#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XRAY_RUNTIME_VERSION="${XRAY_RUNTIME_VERSION:-26.6.1}"
CENTRAL_PUBLISHING_TYPE="${CENTRAL_PUBLISHING_TYPE:-USER_MANAGED}"

: "${MAVEN_CENTRAL_USERNAME:?Set MAVEN_CENTRAL_USERNAME to your Central Portal token username.}"
: "${MAVEN_CENTRAL_PASSWORD:?Set MAVEN_CENTRAL_PASSWORD to your Central Portal token password.}"
: "${SIGNING_IN_MEMORY_KEY:?Set SIGNING_IN_MEMORY_KEY to an ASCII-armored private GPG key.}"
: "${SIGNING_IN_MEMORY_KEY_PASSWORD:?Set SIGNING_IN_MEMORY_KEY_PASSWORD to the GPG key password.}"

"$ROOT_DIR/tool/build_android_runtime_maven.sh"

BUNDLE_PATH="$ROOT_DIR/android_runtime/xray_android/build/xray-android-$XRAY_RUNTIME_VERSION-central-bundle.zip"
AUTH_TOKEN="$(printf '%s:%s' "$MAVEN_CENTRAL_USERNAME" "$MAVEN_CENTRAL_PASSWORD" | base64 | tr -d '\n')"
DEPLOYMENT_NAME="xray-android-$XRAY_RUNTIME_VERSION"
UPLOAD_URL="https://central.sonatype.com/api/v1/publisher/upload?publishingType=$CENTRAL_PUBLISHING_TYPE&name=$DEPLOYMENT_NAME"

DEPLOYMENT_ID="$(
  curl --fail --show-error --silent \
    --request POST \
    --header "Authorization: Bearer $AUTH_TOKEN" \
    --form "bundle=@$BUNDLE_PATH" \
    "$UPLOAD_URL"
)"

echo "Uploaded Maven Central deployment: $DEPLOYMENT_ID"
echo "Publishing type: $CENTRAL_PUBLISHING_TYPE"
echo "Status URL: https://central.sonatype.com/publishing/deployments"
