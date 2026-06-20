# XRay Android Emulator Compatibility v26.6.1

Platform: Android emulator

Changes:

* Rebuilt `libxray.so` against XTLS/Xray-core `v26.6.1` for `x86` and `x86_64`.
* Moved new Android emulator support to the all-ABI Maven runtime `dev.tfox.fluttervless:xray-android:26.6.1.1`.
* Kept this note only as historical context for older release trains.
* New apps get emulator binaries through the main `flutter_vless_android` dependency.

Upstream:

* XTLS/Xray-core `v26.6.1` was published on 2026-06-01 and is marked as a pre-release on GitHub.
* Upstream release commit: `94ffd50060f1cfd5d7482ec90a23a92bdefdff68`.
