# XRay Android Emulator v26.6.1

Platform: Android emulator

Changes:

* Rebuilt `libxray.so` against XTLS/Xray-core `v26.6.1` for `x86` and `x86_64`.
* Kept emulator binaries in the separate `flutter_vless_android_emulator` package for compatibility with older release trains.
* Kept the package aligned with the `flutter_vless_android` 1.1.1 release train.
* New `flutter_vless_android` builds use the all-ABI Maven runtime `dev.tfox.fluttervless:xray-android:26.6.1.1`, so this package is no longer required by new apps.

Upstream:

* XTLS/Xray-core `v26.6.1` was published on 2026-06-01 and is marked as a pre-release on GitHub.
* Upstream release commit: `94ffd50060f1cfd5d7482ec90a23a92bdefdff68`.
