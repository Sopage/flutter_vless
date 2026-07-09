# XRay Android Emulator Compatibility v26.6.27

Changes:

* Rebuilt bundled emulator `libxray.so` binaries against XTLS/Xray-core `v26.6.27` for `x86` and `x86_64`.
* Kept this package marked as legacy because the main Maven runtime `dev.tfox.fluttervless:xray-android:26.6.27.1` includes emulator ABIs.

Upstream:

* XTLS/Xray-core `v26.6.27` was published on 2026-06-27 and is marked as a pre-release on GitHub.
* Release commit: `45cf2898ab12e97a55dd8f1f3d78d903340bdc9e`.

Verification:

* Copy rebuilt `x86` and `x86_64` `libxray.so` files from `android_runtime/xray_android/src/main/jniLibs` into `packages/flutter_vless_android_emulator/android/src/main/jniLibs`.
* Run the emulator package tests.
