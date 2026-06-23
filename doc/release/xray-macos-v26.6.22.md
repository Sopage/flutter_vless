# XRay macOS v26.6.22

Release tag: `xray-macos-v26.6.22`

Changes:

* Rebuilt `XRay.xcframework` against XTLS/Xray-core `v26.6.22`.
* Updated the macOS SwiftPM binary target and CocoaPods default release tag to `xray-macos-v26.6.22`.
* Kept the static-library xcframework packaging used by the macOS plugin and tunnel-support target.
* Build source comes from the vendored `third_party/xray-mobile` Go wrapper.

Upstream:

* XTLS/Xray-core `v26.6.22` was published on 2026-06-22 and is marked as a pre-release on GitHub.
* Release commit: `b99c3e56574fb0317608c49dd1dd9af816db7a9e`.

Verification:

* Run `cd packages/flutter_vless_macos/macos && ./build_xray_macos.sh`.
* Run `tool/create_xray_macos_release.sh` and copy the printed checksum into `packages/flutter_vless_macos/macos/flutter_vless_macos/Package.swift` and `packages/flutter_vless_macos/macos/flutter_vless_macos.podspec`.
