# XRay iOS v26.6.27

Release tag: `xray-ios-v26.6.27`

Changes:

* Rebuilt `XRay.xcframework` against XTLS/Xray-core `v26.6.27`.
* Updated the iOS SwiftPM binary target and CocoaPods default release tag to `xray-ios-v26.6.27`.
* Kept the iOS minimum deployment target at 15.0.
* Build source comes from the vendored `third_party/xray-mobile` Go wrapper.

Upstream:

* XTLS/Xray-core `v26.6.27` was published on 2026-06-27 and is marked as a pre-release on GitHub.
* Release commit: `45cf2898ab12e97a55dd8f1f3d78d903340bdc9e`.

Verification:

* Run `cd ios && ./build_xray_ios.sh`.
* Run `tool/create_xray_ios_release.sh` and copy the printed checksum into `ios/flutter_vless/Package.swift` and `ios/flutter_vless.podspec`.
