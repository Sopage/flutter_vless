# Getting Started

This guide is for developers who want to add `flutter_vless` to an app and get a working connection with the smallest possible amount of setup.

## Quick Run From The Example

The fastest way to verify your environment is to run the bundled example app
first, then copy the same setup shape into your project.

```bash
cd example
flutter pub get
```

Then run the target you care about:

```bash
flutter run -d android
flutter run -d ios
flutter run -d macos
flutter run -d windows
```

Platform caveats still apply: iOS needs a real signed device for VPN mode,
macOS needs the Packet Tunnel setup, and Windows needs `xray.exe` in place.

## 1. Add The Dependency

```yaml
dependencies:
  flutter_vless: ^1.1.0
```

Then run:

```bash
flutter pub get
```

If you need Android emulator support, also add:

```bash
flutter pub add flutter_vless_android_emulator
```

## 2. Complete Platform Setup

Read the platform-specific guide that matches your target:

- [Android](platform/android.md)
- [iOS](platform/ios.md)
- [macOS](platform/macos.md)
- [Windows](platform/windows.md)

For version requirements, native binaries, and known platform limits, read
[Compatibility](compatibility.md).

## 3. Initialize The Plugin

The snippet below assumes these imports:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
```

```dart
final flutterVless = FlutterVless(
  onStatusChanged: (status) {
    debugPrint(
      'state=${status.state} connection=${status.connectionState.name} '
      'download=${status.download}',
    );
  },
);

await flutterVless.initializeVless(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

## 4. Import A Share Link Or Subscription

```dart
final parsed = FlutterVless.parse(shareLink);
final config = parsed.getFullConfiguration();
```

Use `FlutterVless.parseMany(subscriptionText)` when you want every supported profile from a subscription payload.

## 5. Start The Connection

```dart
if (await flutterVless.requestPermission()) {
  await flutterVless.startVless(
    remark: parsed.remark,
    config: config,
  );
}
```

If you are running proxy-only mode, you can skip the VPN permission step on the paths that do not require a tunnel.

## 6. Stop The Connection

```dart
await flutterVless.stopVless();
```

## A Practical Mental Model

1. Parse user input into a `FlutterVlessURL`.
2. Turn that into a JSON Xray config.
3. Initialize the platform implementation.
4. Start proxy-only mode or VPN/tunnel mode.
5. Read status updates and delay metrics from the platform channel.

Next reads:

- [API Contract](api.md)
- [Examples](examples.md)
- [Security And Runtime Boundaries](security.md)
