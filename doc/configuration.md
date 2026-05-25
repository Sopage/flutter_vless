# Configuration Guide

`flutter_vless` has two configuration layers:

1. Input parsing
2. Runtime Xray JSON generation

The public API intentionally keeps both layers accessible, because different users need different levels of control.

## Supported Inputs

`FlutterVless.parse()` and `FlutterVless.parseMany()` accept:

- single share links such as `vmess://`, `vless://`, `trojan://`, `ss://`, and `socks://`
- raw Xray JSON
- base64-encoded subscription payloads
- Clash YAML
- sing-box JSON

Unsupported sing-box-only protocols are skipped instead of being converted into broken Xray output.

## `parse()` Versus `parseMany()`

- Use `parse()` when you have one link or one config and want the first supported profile.
- Use `parseMany()` when you want to preserve every supported profile from a subscription payload.

This distinction matters when a payload contains several profiles or when you are importing from a clipboard source that mixes formats.

## Advanced Editing

The parsed objects expose low-level Xray maps. That makes advanced editing possible, but it also means the API is intentionally closer to Xray than to a high-level convenience wrapper.

The snippet below assumes:

```dart
import 'package:flutter_vless/flutter_vless.dart';
```

Examples:

```dart
final parsed = FlutterVless.parse(shareLink);

parsed.inbound['port'] = 10890;
parsed.inbound['listen'] = '0.0.0.0';
parsed.routing['domainStrategy'] = 'AsIs';

final config = parsed.getFullConfiguration();
```

Use this layer when you need custom routing, custom inbound ports, or platform-specific tweaks that are not covered by the share-link surface.

## Typed Config Helpers

If you prefer to build or validate config in a more explicit way, use the typed
helpers in `lib/url/xray_config_model.dart` and
`lib/url/xray_config_validator.dart`.

Example:

```dart
import 'package:flutter_vless/url/xray_config_model.dart';
import 'package:flutter_vless/url/xray_config_validator.dart';

const validator = XrayConfigValidator();

final doc = XrayConfigDocument(
  log: const XrayLog(),
  inbounds: [
    XrayInbound.localSocksTunnel(),
  ],
  outbounds: [
    XrayOutbound.direct(),
    XrayOutbound.blackhole(),
  ],
  routing: const XrayRouting(),
);

final jsonMap = doc.toJson();
validator.validate(jsonMap);
```

The same validator is used by `FlutterVless.startVless()` and
`FlutterVless.getServerDelay()` before the config is forwarded to native code.

## What The Parser Preserves

The parser keeps server-provided details that are easy to lose in a simplified URL-to-config conversion, including:

- VLESS `encryption`
- TLS and Reality settings
- XHTTP extra fields when they are present
- subscription payload structure when multiple profiles exist

## What The Parser Does Not Promise

- It does not convert every sing-box-only protocol into Xray.
- It does not guarantee that every imported config will work on every platform.
- It does not validate that a config is operational on the network you are currently using.

If you use the typed helpers, you still need to ensure that the resulting
outbound actually matches the transport details you want to run on the target
platform.

For platform-specific behavior, pair this guide with the platform docs and the troubleshooting guide.
