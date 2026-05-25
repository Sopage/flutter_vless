# macOS

macOS uses a Packet Tunnel Network Extension path for VPN mode and a separate local proxy path for proxy-only mode.

## What You Need

- macOS 13 or newer for the validated setup
- a Packet Tunnel extension target
- App Groups enabled
- the setup command from the package

## Recommended Setup Command

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
- use the architecture note before changing packet tunnel logic

## Common Pitfalls

- mixing up the base bundle id and the extension bundle id
- changing routing without checking DNS reachability
- assuming proxy-only delay results prove packet-tunnel health
