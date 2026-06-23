# XRay iOS v26.6.1

Platform: iOS

Changes:

* Rebuilt `XRay.xcframework` against XTLS/Xray-core `v26.6.1`.
* Updated the iOS SwiftPM binary target and CocoaPods default release tag to `xray-ios-v26.6.1`.
* Kept the iOS minimum deployment target at 15.0.
* Build source now comes from the vendored `third_party/xray-mobile` Go wrapper instead of cloning the upstream wrapper repository.

Upstream:

* XTLS/Xray-core `v26.6.1` was published on 2026-06-01 and is marked as a pre-release on GitHub.
* Upstream release commit: `94ffd50060f1cfd5d7482ec90a23a92bdefdff68`.
