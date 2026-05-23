## 1.0.5

* Fixed Android VPN startup with configs that already include custom SOCKS/HTTP inbounds.
* Added automatic port conflict handling for local SOCKS, HTTP, and Xray API inbounds.
* Added support for flat VLESS outbound configs by normalizing them to Xray `vnext/users` format.
* Fixed server IP exclusion parsing for flat VLESS configs to avoid VPN routing loops.
* Sanitized Android Xray log paths so desktop/macOS paths do not break startup.
* Improved Xray startup validation to avoid reporting connected state when the core exits immediately.
* Added a fallback notification icon for Android foreground service notifications.
* Updated the bundled XRay core version.
* Added Swift Package Manager support for the iOS implementation.
* Added automatic download and checksum validation for the prebuilt `XRay.xcframework`.
* Added a separate `flutter-vless-tunnel-support` SwiftPM product for iOS Packet Tunnel extensions.
* Reworked the iOS plugin source layout for SwiftPM and CocoaPods compatibility.
* Updated the iOS CocoaPods spec with proper package metadata, iOS 15 minimum target, and XRay release handling.
* Updated the example iOS project to use local Swift packages instead of manually embedded XRay and Tun2Socks frameworks.
* Updated iOS setup documentation with SwiftPM, Packet Tunnel, App Groups, and CocoaPods fallback instructions.
* Updated README examples to pass the base app bundle identifier; the plugin now appends `.XrayTunnel` internally.
* Excluded local `ios/XRay.xcframework` artifacts from the published package.
* Documented Xray VLESS Encryption handling for `mlkem768x25519plus...` values and why they cannot be inferred from bare `vless://` links.
* Added raw Xray JSON/JSON-array import support so Happ-style configs preserve server-provisioned `users[].encryption` values 1:1.
* Updated the example importer and real-device smoke test to use the universal parser for both share URLs and raw Xray JSON.
* Added Dart coverage for VLESS XHTTP/none, VLESS Encryption passthrough, raw Xray JSON import, SS/SOCKS compatibility formats, and iOS/Android MethodChannel arguments.
* Extracted iOS Packet Tunnel Xray JSON preparation into a Swift testable helper with coverage for log/DNS cleanup, XHTTP UDP/443 routing, proxy server parsing, and VLESS Encryption preservation.
* Added `FlutterVless.parseMany` subscription import support for base64 share-link lists, Clash YAML, and sing-box JSON for supported Xray protocols.
* Added Android native Kotlin unit tests for runtime Xray config injection, local port conflict handling, flat VLESS normalization, and log path sanitization.
* Added CI coverage for Flutter tests, Android native unit tests, Swift PacketTunnel helper tests, and an iOS no-codesign example build.
* Added a physical-device VPN matrix script/documentation for TCP/Reality, XHTTP/Reality, XHTTP/none with VLESS Encryption, Shadowsocks, Trojan, and VMess.
* Fixed universal parsing of single VLESS Reality share links so example clipboard import does not route them through subscription heuristics.
* Fixed Android server-delay probing to reuse the same runtime Xray config normalization as normal startup.
* Added iOS proxy-only startup through in-app Xray without starting the Packet Tunnel, and skipped VPN permission in the example when proxy-only mode is selected.
* Forced iOS CocoaPods generated targets to deployment target 15.0 and added an example reset script so integration tests cannot leave the app launching Flutter's test listener.

## 1.0.4

* feat: XRay version up

## 1.0.3

* fix: no such module 'XRay' 

* feat: code formatted

## 1.0.2

*   **Refactor**: Migrated to a Federated Plugin architecture.
    *   Split into `flutter_vless` (app-facing), `flutter_vless_platform_interface` (common), and `flutter_vless_android` (Android implementation).
    *   This structure improves maintainability.

*   **Android**:
    *   **Migration to Kotlin**: Complete rewrite of Android native code from Java to Kotlin.
    *   **16KB Page Size**: Added support for Android devices with 16KB page sizes (API 35+).

*   **Docs**: Added comprehensive documentation to Android native code.

## 1.0.1

* feat: upgrade xray version and update documentation

* refactor: modify V2rayCoreManager to use CoreController and improve lifecycle management

* fix: enhance error handling in V2rayProxyOnlyService and V2rayVPNService

* style: adjust spacing in main.dart for better UI layout

* docs: improve descriptions and comments in V2ray services for clarity

* chore: update pubspec.yaml with additional tags and improved description

## 1.0.0

* init
