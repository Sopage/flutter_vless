# Troubleshooting

This guide is intentionally practical. Use it when the app compiles but the connection does not behave the way you expect.

## VPN Permission Is Granted, But Traffic Does Not Flow

Check:

- `providerBundleIdentifier` matches the base app bundle id, not the extension id
- `groupIdentifier` matches the App Group used by the native target
- the platform setup guide has been followed completely
- the platform actually supports the mode you are trying to use

## The Connection Starts, But Browsing Is Stalled

Common causes:

- DNS is misconfigured
- the server route loops back into the tunnel
- the wrong platform guide was followed
- a proxy-only example was copied into a VPN flow, or vice versa

## `parse()` Fails On A Link

Check whether the input really is one of the supported formats:

- `vmess://`
- `vless://`
- `trojan://`
- `ss://`
- `socks://`
- raw Xray JSON
- base64 subscription text
- Clash YAML
- sing-box JSON

If the input is a subscription payload, try `FlutterVless.parseMany()` first so you can see every supported profile.

## `startVless()` Rejects My Config Before Native Code

That usually means the JSON is structurally invalid, not just unsupported by the
server.

Check:

- the config is a JSON object, not an array
- `outbounds` exists and is not empty
- each outbound has a `protocol`
- if you are building configs manually, use the typed helpers in
  `lib/url/xray_config_model.dart`

## Android Specific

- confirm Gradle `packaging.jniLibs.useLegacyPackaging = true` is set when extracted native executables are required
- confirm `minSdkVersion` is high enough
- confirm the app resolves the current Maven runtime AAR, which includes emulator ABIs
- confirm `blockedApps` is only used where the platform backend supports it

## iOS And macOS Specific

- use a real device for tunnel validation
- confirm the Packet Tunnel target is signed
- confirm the App Group is shared between the app and the extension
- for macOS, read the packet tunnel architecture note before changing routing or DNS

## Windows Specific

- confirm `xray.exe` is available where the plugin expects it
- confirm the current process has enough permissions for system routing changes
- confirm proxy-only and VPN mode are not being mixed up

## When In Doubt

Use the bundled example app, then compare its behavior with the docs. The example is often the quickest way to see whether the problem is in your app code or in platform setup.
