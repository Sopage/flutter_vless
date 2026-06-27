## 1.1.3

* Updated the macOS XRay core target to upstream `v26.6.22`.
* Updated the default macOS SwiftPM/CocoaPods release tag to `xray-macos-v26.6.22`.
* Fixed macOS Packet Tunnel VPN routing for VLESS + XHTTP + TLS configs by using the validated local TUN gateway model (`127.0.0.1` remote label, `198.18.0.1/24` local address, default gateway `198.18.0.1`).
* Published explicit Packet Tunnel DNS with `matchDomains = [""]` and kept DNS host-route exclusions disabled for the working macOS route model.
* Added provider/app diagnostics for raw `utun` TCP reachability, interface-bound probes, HEV fd selection, Xray/SOCKS health checks, and expanded shared provider logs.
* Fixed macOS SwiftPM builds by explicitly importing the `CXRay` shim before using `XRayLoggerProtocol`.
* Restored Xcode 15.x compatibility for the bundled macOS example project by replacing newer synchronized project groups with legacy Xcode project groups.
* Hardened `prepare_apple_swiftpm.sh` for copied repository checkouts by normalizing generated SwiftPM paths, resolving Apple packages, and clearing stale DerivedData package caches.

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
