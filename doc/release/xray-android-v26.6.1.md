# XRay Android v26.6.1

Platform: Android device

Changes:

* Rebuilt `libxray.so` against XTLS/Xray-core `v26.6.1` for `arm64-v8a` and `armeabi-v7a`.
* Kept 16KB page-size linker alignment for Android 15+ compatibility.
* Kept emulator ABIs out of the main Android package.

Upstream:

* XTLS/Xray-core `v26.6.1` was published on 2026-06-01 and is marked as a pre-release on GitHub.
* Upstream release commit: `94ffd50060f1cfd5d7482ec90a23a92bdefdff68`.
