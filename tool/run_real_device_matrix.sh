#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
DEVICE_ID="${DEVICE_ID:-}"
TARGET="integration_test/vpn_smoke_test.dart"
RESET_EXAMPLE_APP_MODE="${VPN_MATRIX_RESET_EXAMPLE_APP_MODE:-true}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Set DEVICE_ID to a physical iOS or Android device id from: flutter devices" >&2
  exit 2
fi

reset_example_app_mode() {
  if [[ "$RESET_EXAMPLE_APP_MODE" == "true" ]]; then
    "$ROOT_DIR/tool/reset_example_app_mode.sh"
  fi
}

trap reset_example_app_mode EXIT

run_case() {
  local name="$1"
  local url="$2"
  local require_browser="${3:-false}"

  if [[ -z "$url" ]]; then
    echo "SKIP $name: URL/config env is empty"
    return 0
  fi

  echo "RUN $name on $DEVICE_ID"
  (
    cd "$EXAMPLE_DIR"
    flutter test "$TARGET" \
      -d "$DEVICE_ID" \
      --dart-define="VPN_TEST_URL=$url" \
      --dart-define="VPN_REQUIRE_BROWSER_TRAFFIC=$require_browser"
  )
}

run_case "tcp-reality" "${VPN_MATRIX_TCP_REALITY_URL:-}" "${VPN_MATRIX_REQUIRE_BROWSER_TRAFFIC:-false}"
run_case "xhttp-reality" "${VPN_MATRIX_XHTTP_REALITY_URL:-}" "${VPN_MATRIX_REQUIRE_BROWSER_TRAFFIC:-false}"
run_case "xhttp-none-json" "${VPN_MATRIX_XHTTP_NONE_JSON:-}" "${VPN_MATRIX_REQUIRE_BROWSER_TRAFFIC:-false}"
run_case "shadowsocks" "${VPN_MATRIX_SHADOWSOCKS_URL:-}" "${VPN_MATRIX_REQUIRE_BROWSER_TRAFFIC:-false}"
run_case "trojan" "${VPN_MATRIX_TROJAN_URL:-}" "${VPN_MATRIX_REQUIRE_BROWSER_TRAFFIC:-false}"
run_case "vmess" "${VPN_MATRIX_VMESS_URL:-}" "${VPN_MATRIX_REQUIRE_BROWSER_TRAFFIC:-false}"

if [[ -n "${VPN_MATRIX_PROXY_ONLY_URL:-}" ]]; then
  echo "RUN proxy-only on $DEVICE_ID"
  (
    cd "$EXAMPLE_DIR"
    flutter test "$TARGET" \
      -d "$DEVICE_ID" \
      --dart-define="VPN_TEST_URL=$VPN_MATRIX_PROXY_ONLY_URL" \
      --dart-define="VPN_PROXY_ONLY=true"
  )
fi
