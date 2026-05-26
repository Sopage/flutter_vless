# Examples

These examples focus on the Dart API. Platform setup still has to be completed
before VPN/tunnel mode can work.

## 1. Proxy-Only Start

Use proxy-only mode when you want local Xray proxy behavior without installing a
system VPN route.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';

final flutterVless = FlutterVless(
  onStatusChanged: (status) {
    debugPrint('state=${status.connectionState.name}');
  },
);

Future<void> startProxyOnly(String link) async {
  final parsed = FlutterVless.parse(link);

  await flutterVless.initializeVless();

  await flutterVless.startVless(
    remark: parsed.remark,
    config: parsed.getFullConfiguration(),
    proxyOnly: true,
  );
}
```

## 2. VPN Or Packet Tunnel Start

Use VPN/tunnel mode when the app should route system traffic through the native
VPN or Packet Tunnel path.

```dart
Future<void> startTunnel(String link) async {
  final parsed = FlutterVless.parse(link);

  await flutterVless.initializeVless(
    providerBundleIdentifier: 'com.example.myapp',
    groupIdentifier: 'group.com.example.myapp',
  );

  final allowed = await flutterVless.requestPermission();
  if (!allowed) {
    return;
  }

  await flutterVless.startVless(
    remark: parsed.remark,
    config: parsed.getFullConfiguration(),
    bypassSubnets: const ['192.168.0.0/16', '10.0.0.0/8'],
  );
}
```

Notes:

- Android can use `blockedApps` for per-app VPN exclusions.
- iOS and macOS require Network Extension and App Group setup.
- Windows tunnel behavior may require elevated permissions.

## 3. Import A Subscription

Use `parseMany()` when the input can contain more than one profile.

```dart
Future<List<String>> importSubscription(String subscriptionText) async {
  final profiles = FlutterVless.parseMany(subscriptionText);

  return profiles.map((profile) {
    return profile.getFullConfiguration();
  }).toList();
}
```

`parseMany()` supports base64 share-link lists, Clash YAML, sing-box JSON, and
raw payloads containing supported Xray-compatible protocols.

## 4. Custom Routing

Use the parsed object's mutable Xray maps when you need to adjust generated
runtime config before startup.

```dart
Future<void> startWithCustomRouting(String link) async {
  final parsed = FlutterVless.parse(link);

  parsed.inbound['port'] = 10890;
  parsed.inbound['listen'] = '127.0.0.1';
  parsed.routing['domainStrategy'] = 'AsIs';
  parsed.routing['rules'] = [
    {
      'type': 'field',
      'domain': ['geosite:private'],
      'outboundTag': 'direct',
    },
  ];

  await flutterVless.startVless(
    remark: parsed.remark,
    config: parsed.getFullConfiguration(),
    proxyOnly: true,
  );
}
```

For deeper config work, pair this with `configuration.md` and the platform guide
for the target operating system.

