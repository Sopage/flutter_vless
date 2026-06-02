## 1.1.1

* Updated bundled Android device `libxray.so` binaries to Xray-core `v26.6.1`.
* Kept Android 15+ 16KB page-size linker alignment for the rebuilt ARM binaries.
* Made emulator ABI builds opt-in so the device package keeps only ARM native libraries.

## 1.1.0

* Replaced Android Dart boilerplate with the shared `VlessMethodChannelAdapter`.
* Removed template `getPlatformVersion` scaffold files.
* Moved `flutter_lints` to `dev_dependencies`.
* Removed publish-time dependency overrides from `pubspec.yaml`.

## 1.0.2

* XRay version up

## 1.0.1

*   XRay version up

## 1.0.0

*   Initial release of the Android implementation for `flutter_vless`.
*   Supports VLESS/VMESS protocols using Xray core.
*   Implements `VlessPlatform` interface.
