# Security And Runtime Boundaries

`flutter_vless` starts local Xray-backed proxy or VPN/tunnel runtimes from a
Flutter app. This page documents what the package does locally and what remains
the app developer's responsibility.

## What The Package Does

- Parses supported proxy links, subscriptions, Clash YAML, sing-box JSON, and
  raw Xray JSON into Xray-compatible configuration.
- Starts local Xray-backed proxy-only or tunnel mode through native platform
  code.
- Requests platform permissions needed for VPN/tunnel mode.
- Emits runtime status, byte counters, and delay measurements through Dart.
- Cleans up platform runtime state where the backend controls it, such as local
  Xray processes, foreground services, tunnel state, or system proxy settings.

## Native Binaries

The package relies on native Xray artifacts.

Platform notes:

- Android packages native `libxray.so` libraries.
- iOS and macOS use Xray framework artifacts through CocoaPods/Swift Package
  integration.
- Windows expects a local `xray.exe`; the plugin does not download it at
  runtime.

Treat native binary updates as release-sensitive work. Keep checksums, release
tags, and platform package versions aligned.

## User And Server Responsibility

The app or end user is responsible for the proxy server configuration being
legal, trusted, and operational.

The package can validate that a config is structurally usable as Xray JSON. It
cannot prove that:

- the remote server is trustworthy
- the subscription source is safe
- the server owner permits the intended usage
- the config is legal in the user's jurisdiction
- the network path is private against every attacker model

Do not treat successful startup as a security audit of the server.

## Permissions

VPN/tunnel mode may request sensitive operating-system permissions:

- Android VPN service and notification-related permission flows.
- iOS/macOS Network Extension profile and App Group access.
- Windows system proxy or routing changes, depending on mode.

Proxy-only mode is lighter because it starts local proxy behavior without
installing a VPN route, but it can still affect system proxy settings on desktop
platforms depending on the backend path.

## Config Handling

`startVless()` and `getServerDelay()` validate config structure before sending
the JSON to native code. This catches malformed JSON and missing outbound
sections early, but it is not a full semantic validator for every Xray protocol
combination.

Recommended app behavior:

- show the imported profile name and server host before connecting
- handle `ArgumentError` from invalid configs
- let users remove imported subscriptions and profiles
- avoid logging full configs when they contain credentials, UUIDs, keys, or
  server addresses

## Logging

Debug logs can contain server addresses, transport details, route decisions,
and runtime errors. Avoid uploading logs automatically unless the user has
reviewed them.

For support flows, prefer redacting:

- UUIDs
- passwords
- private keys
- subscription URLs
- server hostnames or IPs when the user asks for privacy

## Recommended Production Checklist

- Pin package versions in the app.
- Verify native binary checksums during release work.
- Test VPN/tunnel mode on real devices.
- Keep proxy-only and tunnel mode clearly separated in UI.
- Provide a user-visible disconnect action.
- Avoid silently importing unsupported protocols.
- Document what traffic the app routes and when the local runtime is active.

