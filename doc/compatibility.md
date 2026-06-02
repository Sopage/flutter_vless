# Compatibility

This page lists the expected platform shape for `flutter_vless`.

## Package Scope

`flutter_vless` is a federated Flutter plugin for Xray/V2Ray-compatible client
flows:

- VLESS
- VMESS
- Trojan
- Shadowsocks
- SOCKS
- raw Xray JSON
- supported Clash YAML and sing-box import paths

It is not a general sing-box runtime. sing-box-only protocols that cannot be
represented as Xray config are skipped by the parser.

## Platform Matrix

| Platform | Supported modes | Minimum / validated version | Native requirement | Main limitations |
| --- | --- | --- | --- | --- |
| Android | VPN, proxy-only | `minSdk` 23, target SDK 35 in the Android package | Xray runtime AAR from Maven Central; `android:extractNativeLibs="true"` in the app manifest when required | Main package targets ARM device ABIs; emulator ABIs live in `flutter_vless_android_emulator`. |
| iOS | VPN, proxy-only | iOS 15.0+ | Network Extension, Packet Tunnel target, App Group, signed real device for tunnel validation | Simulator is not a reliable VPN/tunnel test target. |
| macOS | VPN, proxy-only | macOS 13.0+ for the validated setup | Packet Tunnel extension, App Group, Swift Package products, setup command | Packet Tunnel routing and DNS changes must follow the architecture note. |
| Windows | VPN/tunnel, proxy-only | Recent Flutter Windows toolchain | Local `xray.exe` available to the app | Tunnel/system routing may require elevated permissions; the plugin does not download Xray for you. |
| Web | Not supported | N/A | N/A | No web implementation is registered. |

## Android

The Android implementation includes 16KB page size support for modern Android
builds and bundles native Xray libraries for device ABIs.

For emulator targets, add:

```bash
flutter pub add flutter_vless_android_emulator
```

The app manifest should place native library extraction on the `<application>`
tag:

```xml
<application
    android:name="${applicationName}"
    android:extractNativeLibs="true">
    ...
</application>
```

## Apple Platforms

iOS and macOS use Apple's Network Extension model for tunnel mode.

Required for tunnel mode:

- Packet Tunnel extension target
- Network Extension capability
- App Group shared between the app and extension
- matching signing team/profile setup

Pass the base app bundle id to Dart:

```dart
await flutterVless.initializeVless(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

The plugin appends the Packet Tunnel extension suffix internally.

## Windows Xray Lookup

Windows needs a local `xray.exe`. Common lookup locations include:

```text
windows/xray/xray.exe
xray/xray.exe
xray.exe
data/flutter_assets/xray/xray.exe
%APPDATA%/flutter_vless/xray.exe
```

The bundled example expects:

```text
example/windows/xray/xray.exe
```

## Known Product Boundaries

- No web implementation.
- No automatic Windows Xray download.
- No guarantee that every imported server config works on every platform.
- No automatic conversion for protocols that Xray cannot run.
- VPN/tunnel mode depends on operating-system permissions and native project
  setup, not only Dart code.
