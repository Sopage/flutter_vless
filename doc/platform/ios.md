# iOS

iOS uses a Network Extension packet tunnel path.

## What You Need

- a real Apple Developer account and a signing-capable iPhone
- a Packet Tunnel extension target
- App Groups enabled on both the app and the tunnel target
- the same base app bundle id passed from Dart

## Bundle Id Convention

Pass the base app bundle id to `initializeVless()`:

```dart
await flutterVless.initializeVless(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

The plugin appends `.XrayTunnel` internally for the tunnel extension.

## Runtime Notes

- real-device testing is strongly preferred
- `proxyOnly: true` avoids the tunnel path
- `bypassSubnets` is the route-level knob to understand first
- app-level blocking is not the same thing as tunnel routing

## Suggested Setup Flow

1. Add the package.
2. Create the Packet Tunnel extension.
3. Enable App Groups and Network Extensions.
4. Pass the base bundle id and App Group from Dart.
5. Test on a real device.

## Common Pitfalls

- signing the app but not the extension
- using the extension bundle id instead of the base app bundle id
- expecting simulator behavior to match a real device
