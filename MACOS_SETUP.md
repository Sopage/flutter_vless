# macOS VPN setup

The macOS VPN path is configured by the setup command. It creates or updates
the `XrayTunnel` Network Extension target, writes the tunnel plist and
entitlements, embeds the extension into `Runner`, and links the
`flutter-vless-macos-tunnel-support` SwiftPM product.

The tunnel support product pulls in:

- XRay
- Tun2SocksKit
- Tun2SocksKitC
- libresolv
- the shared packet tunnel provider implementation

That means app projects should not copy the full tunnel provider or manually
link `XRay.xcframework`.

The supported macOS deployment target is 13.0 or newer. The setup command
normalizes every `MACOSX_DEPLOYMENT_TARGET` in the Xcode project to the selected
deployment target so older generated 10.15 settings cannot leak back into
SwiftPM or CocoaPods builds.

For the Packet Tunnel routing model, DNS/route invariants, health-check
semantics, and the regression checklist, read
[doc/macos_packet_tunnel_architecture.md](./doc/macos_packet_tunnel_architecture.md)
before changing the macOS tunnel provider.

## 1. Run the setup command

From your Flutter app root:

```bash
dart run flutter_vless:setup_macos_vpn \
  --bundle-id com.example.myapp \
  --group-id group.com.example.myapp \
  --team-id ABCDE12345
```

Optional:

```bash
dart run flutter_vless:setup_macos_vpn \
  --project-dir /path/to/app \
  --bundle-id com.example.myapp \
  --group-id group.com.example.myapp \
  --team-id ABCDE12345 \
  --deployment-target 13.0
```

Use the base app bundle id. The command configures the tunnel extension as:

```text
com.example.myapp.XrayTunnel
```

The command is safe to run again after changing ids or regenerating Flutter
macOS files.

## 2. Check Apple signing

Open `macos/Runner.xcworkspace` in Xcode and confirm both targets use your
team:

- `Runner`
- `XrayTunnel`

Both targets need the same App Group. `XrayTunnel` also needs the Network
Extension entitlement with Packet Tunnel enabled.

The command writes these entitlements, but Apple Developer provisioning must
allow them for your bundle ids.

## 3. Initialize from Dart

Pass the same base app bundle id and App Group:

```dart
await flutterVless.initializeVless(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

The plugin appends `.XrayTunnel` internally.

## 4. Build

```bash
flutter build macos --debug
```

Or run from Xcode using `Runner.xcworkspace`.

## Troubleshooting

If the VPN permission is granted but the tunnel does not start, check:

- `providerBundleIdentifier` is the base app id, not the extension id.
- `groupIdentifier` matches the App Group in both targets.
- The provisioning profile allows Network Extensions.
- `XrayTunnel` links `flutter-vless-macos-tunnel-support`, not a manual
  `XRay.xcframework`.

Useful logs:

```bash
log stream --predicate 'subsystem contains "XrayTunnel" OR eventMessage contains "XRay" OR eventMessage contains "HEV"' --info
```

Healthy Packet Tunnel runs should also show the provider debug markers described
in [macOS Packet Tunnel Architecture and Regression Notes](./doc/macos_packet_tunnel_architecture.md),
especially:

- `System DNS published with route exclusions: 1.1.1.1,8.8.8.8`
- `Server TCP route health check: ok <server-ip>:443`
- `SOCKS HTTP health check: ok 1.1.1.1/cdn-cgi/trace ...`
- `SOCKS URLSession HTTPS health check: ok status=204`
- default IPv4 route through `utun`, DNS/server host routes through the primary
  interface
