# flutter_vless_android

The Android implementation of the `flutter_vless` plugin.

## Runtime

Android device runtime binaries and geodata are delivered through the Maven Central AAR dependency `dev.tfox.fluttervless:xray-android:26.6.1`. This keeps the Pub.dev package lightweight while preserving the same packaged Xray files in the final Android app.

## Emulator Support (x86_64)

To reduce the package size, x86_64 binaries (required for most emulators) have been moved to a separate package: `flutter_vless_android_emulator`.

If you need to run your app on an x86_64 emulator, please add `flutter_vless_android_emulator` to your `pubspec.yaml` dependencies.
