## 1.1.3

* Fixed macOS SwiftPM builds by explicitly importing the `CXRay` shim before using `XRayLoggerProtocol`.

## 1.1.2

* Fixed Packet Tunnel setup for hosted Pub packages whose generated SwiftPM symlink includes the package version.
* Patched existing Xcode local Swift package references when they still point at a stale unversioned package path.

## 1.1.1

* Updated the macOS XRay core target to upstream `v26.6.1`.
* Updated the default macOS SwiftPM/CocoaPods release tag to `xray-macos-v26.6.1`.
* Kept the static-library `XRay.xcframework` packaging path for Apple Silicon and Intel macOS targets.

## 1.1.0

* Added the macOS implementation package for `flutter_vless`.
* Added support for Xray-backed proxy-only and Packet Tunnel flows.
* Added shared platform-channel integration through `flutter_vless_platform_interface`.
