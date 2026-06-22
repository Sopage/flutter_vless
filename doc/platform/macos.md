# macOS

macOS uses a Packet Tunnel Network Extension path for VPN mode and a separate local proxy path for proxy-only mode.

## Quick Run The Example

Use the example app first if you want to verify that Xcode signing, the Packet
Tunnel target, and the Swift package products are wired correctly.

```bash
cd example
flutter pub get
open macos/Runner.xcworkspace
```

Set your Apple Team on both macOS targets, then run from Xcode or:

```bash
flutter run -d macos
```

## What You Need

- macOS 13 or newer for the validated setup
- a Packet Tunnel extension target
- App Groups enabled
- the setup command from the package

## Recommended Setup Command

For your own app, run the setup command from your Flutter app root:

```bash
dart run flutter_vless:setup_macos_vpn \
  --bundle-id com.example.myapp \
  --group-id group.com.example.myapp \
  --team-id ABCDE12345
```

## Bundle Id Convention

Pass the base app bundle id to `initializeVless()`:

```dart
await flutterVless.initializeVless(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

## What To Read Next

- [macos_packet_tunnel_architecture.md](../macos_packet_tunnel_architecture.md)

That note explains the routing, DNS, and packet-tunnel invariants that matter when you touch the macOS backend.

## Runtime Notes

- proxy-only mode and tunnel mode are different code paths
- the packet tunnel is more sensitive to DNS and route configuration than a normal proxy-only start
- the validated Packet Tunnel route model uses `127.0.0.1` as the Network Extension remote label, `198.18.0.1/24` as the local TUN address, `198.18.0.1` as the default route gateway, explicit DNS servers `1.1.1.1` and `8.8.8.8`, and no DNS host-route exclusions
- a healthy VPN run should include `Packet tunnel DNS servers=1.1.1.1,8.8.8.8 matchDomains=default`, `SOCKS URLSession HTTPS health check: ok status=204`, and app-side raw TCP probes through the selected `utun`
- use the architecture note before changing packet tunnel logic

## PacketTunnelProvider.swift

The example's macOS tunnel target uses a thin provider wrapper:

```text
example/macos/XrayTunnel/PacketTunnelProvider.swift
```

The shared implementation lives in the package support target. That keeps app
projects from copying the full provider manually.

## Common Pitfalls

- mixing up the base bundle id and the extension bundle id
- changing routing without checking DNS reachability
- assuming proxy-only delay results prove packet-tunnel health
