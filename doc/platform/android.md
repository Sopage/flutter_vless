# Android

Android supports both VPN mode and proxy-only mode.

## Quick Run The Example

Use the example app when you want to confirm that the native Android pieces are
working before wiring the plugin into your own app.

```bash
cd example
flutter pub get
flutter run -d android
```

For an emulator, add the emulator package first:

```bash
flutter pub add flutter_vless_android_emulator
```

## What You Need

- Flutter package dependency
- Android project configured for the plugin
- `minSdkVersion` of at least 23
- `android:extractNativeLibs="true"` when required by your packaging setup
- Maven Central access, which is normally already present in Flutter Android projects

## AndroidManifest.xml

Add `android:extractNativeLibs="true"` to the `<application>` tag in:

```text
android/app/src/main/AndroidManifest.xml
```

Example:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="my_app"
        android:name="${applicationName}"
        android:extractNativeLibs="true"
        android:icon="@mipmap/ic_launcher">
        ...
    </application>
</manifest>
```

The bundled example has the same setting in:

```text
example/android/app/src/main/AndroidManifest.xml
```

## Gradle Settings

Make sure your app target can run the plugin:

```kotlin
android {
    defaultConfig {
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
    }
}
```

If your app already uses Flutter's generated values, check what
`flutter.minSdkVersion` resolves to before relying on it.

## Emulator Support

If you need x86_64 emulator support, add the separate `flutter_vless_android_emulator` package.

## Runtime AAR

The Android device runtime is delivered as a Maven Central AAR:

```text
dev.tfox.fluttervless:xray-android:26.6.1
```

The AAR contains the ARM `libxray.so` and `libtun2socks.so` files plus `geoip.dat` and `geosite.dat`. Keeping the runtime in Maven Central avoids Pub.dev archive limits while preserving the same files in the final Android app.

## Runtime Notes

- `blockedApps` is supported on Android.
- `requestPermission()` is relevant for VPN mode.
- `proxyOnly: true` starts the local proxy path without installing the VPN route.

## Suggested Setup Flow

1. Run the example on a device or emulator.
2. Add the dependency to your own app.
3. Add `android:extractNativeLibs="true"` to the application tag.
4. Set `minSdk` to 23 or newer.
5. Initialize the plugin and start proxy-only mode or VPN mode.

## Common Pitfalls

- Using too low a `minSdkVersion`
- Forgetting the native library extraction setting when needed
- Copying iOS or macOS tunnel steps into an Android project
