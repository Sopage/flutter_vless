# XRay Android v26.6.22

Maven runtime: `dev.tfox.fluttervless:xray-android:26.6.22`

Changes:

* Rebuilt `libxray.so` against XTLS/Xray-core `v26.6.22` for `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64`.
* Kept `libtun2socks.so` and Xray geodata packaged in the same runtime AAR.
* Kept Android 15+ 16KB page-size linker alignment for rebuilt Android binaries.
* Updated the Android wrapper default runtime dependency to `dev.tfox.fluttervless:xray-android:26.6.22`.

Upstream:

* XTLS/Xray-core `v26.6.22` was published on 2026-06-22 and is marked as a pre-release on GitHub.
* Release commit: `b99c3e56574fb0317608c49dd1dd9af816db7a9e`.

Verification:

* Run `cd packages/flutter_vless_android/android && ./build_xray.sh`.
* Run `tool/build_android_runtime_maven.sh` and verify the AAR contains all four Android ABIs plus `geoip.dat` and `geosite.dat`.
