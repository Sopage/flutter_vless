# XRay Android v26.6.1

Platform: Android

Changes:

* Rebuilt `libxray.so` against XTLS/Xray-core `v26.6.1` for `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64`.
* Kept 16KB page-size linker alignment for Android 15+ compatibility.
* Moved Android runtime distribution to the Maven Central `dev.tfox.fluttervless:xray-android:26.6.1.1` AAR so Pub.dev receives a lightweight wrapper while Android apps still receive the same native libraries and geodata.
* Included emulator ABIs in the main AAR. The earlier `26.6.1` device-only Maven artifact remains published and immutable, so the all-ABI artifact uses runtime revision `26.6.1.1`.

Upstream:

* XTLS/Xray-core `v26.6.1` was published on 2026-06-01 and is marked as a pre-release on GitHub.
* Upstream release commit: `94ffd50060f1cfd5d7482ec90a23a92bdefdff68`.
