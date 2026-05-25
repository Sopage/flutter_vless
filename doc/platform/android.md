# Android

Android supports both VPN mode and proxy-only mode.

## What You Need

- Flutter package dependency
- Android project configured for the plugin
- `minSdkVersion` of at least 23
- `android:extractNativeLibs="true"` when required by your packaging setup

## Emulator Support

If you need x86_64 emulator support, add the separate `flutter_vless_android_emulator` package.

## Runtime Notes

- `blockedApps` is supported on Android.
- `requestPermission()` is relevant for VPN mode.
- `proxyOnly: true` starts the local proxy path without installing the VPN route.

## Suggested Setup Flow

1. Add the dependency.
2. Set the manifest and SDK values.
3. Initialize the plugin.
4. Parse a link or import a subscription.
5. Start either proxy-only mode or VPN mode.

## Common Pitfalls

- Using too low a `minSdkVersion`
- Forgetting the native library extraction setting when needed
- Copying iOS or macOS tunnel steps into an Android project
