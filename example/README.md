# flutter_vless Example

The example app is the fastest way to verify that platform setup, native Xray
integration, proxy-only mode, tunnel mode, import parsing, and status updates
work before copying the plugin into your own app.

## What It Demonstrates

- Clipboard import through `FlutterVless.parse()`
- Generated Xray config preview and editing
- Proxy-only startup
- VPN/tunnel startup
- Runtime `VlessStatus` updates
- Upload/download counters
- Server core version display
- Android `blockedApps`
- Route/domain editing helpers in `lib/routing.dart`

## Android

Run on a device:

```bash
cd example
flutter pub get
flutter run -d android
```

For Android emulators, the example depends on the local
`flutter_vless_android_emulator` package so x86/x86_64 binaries are available.

The manifest already contains:

```xml
<application
    android:extractNativeLibs="true">
    ...
</application>
```

## iOS

iOS tunnel mode requires a signed real device.

```bash
cd example
flutter pub get
open ios/Runner.xcworkspace
```

In Xcode:

1. Select a real iPhone.
2. Set the same Apple Team for `Runner` and `XrayTunnel`.
3. Confirm App Groups and Network Extension capabilities.
4. Run from Xcode.

After signing is configured, CLI runs can also work:

```bash
flutter run -d <your-iphone-id>
```

## macOS

macOS tunnel mode requires the Packet Tunnel target and signing setup.

```bash
cd example
flutter pub get
open macos/Runner.xcworkspace
```

Set your Apple Team on both macOS targets, then run from Xcode or:

```bash
flutter run -d macos
```

Read `doc/macos_packet_tunnel_architecture.md` before changing macOS routing,
DNS, or Packet Tunnel behavior.

## Windows

Windows needs a local `xray.exe`.

Expected example layout:

```text
example/
  windows/
    xray/
      xray.exe
```

Then run:

```bash
cd example
flutter pub get
flutter run -d windows
```

The Windows backend does not download Xray automatically.

## Common Checks

- Use proxy-only mode first when you want the smallest runtime path.
- Use VPN/tunnel mode only after platform setup is complete.
- Import a known-good share link or raw Xray config from the clipboard.
- Watch `state`, `connectionState`, upload, and download counters after
  startup.
- Stop the session from the app before closing the example during testing.

