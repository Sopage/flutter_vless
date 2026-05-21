# iOS Setup

`flutter_vless` uses an iOS Packet Tunnel extension. XRay is downloaded from
GitHub Releases automatically, so you do not need to copy `XRay.xcframework`
manually.

You still need a real Apple Developer Team because iOS VPN requires signed
Network Extension and App Group entitlements.

## Quick Run Example

The bundled example already contains the `XrayTunnel` extension target.

Use a real iPhone. Packet Tunnel is not a reliable simulator flow.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cd example
flutter pub get
open ios/Runner.xcworkspace
```

In Xcode:

- Select the `Runner` target and set your **Team**.
- Select the `XrayTunnel` target and set the same **Team**.
- Make sure both targets have:
  - **App Groups**
  - **Network Extensions** with **Packet Tunnel**
- Use the same App Group on both targets:

```text
group.dev.tfox.flutterVlessExample
```

Then run from Xcode on your iPhone.

You can also run from CLI after signing is configured:

```bash
flutter run -d <your-iphone-id>
```




## Setup In Your App

### 1. Use Swift Package Manager

Flutter 3.44+ enables SwiftPM by default. For older Flutter versions:

```bash
flutter config --enable-swift-package-manager
```

### 2. Add the dependency

```yaml
dependencies:
  flutter_vless: ^1.0.5
```

```bash
flutter pub get
```

### 3. Create the tunnel extension

Open `ios/Runner.xcworkspace` in Xcode and add a new target:

- Target type: **Network Extension**
- Template: **Packet Tunnel Provider**
- Product Name: `XrayTunnel`
- Bundle Identifier: your app id plus `.XrayTunnel`

Example:

```text
App:    com.example.myapp
Tunnel: com.example.myapp.XrayTunnel
Group:  group.com.example.myapp
```

### 4. Enable capabilities

On both `Runner` and `XrayTunnel`, enable:

- **App Groups**
- **Network Extensions** with **Packet Tunnel**

Use the same App Group on both targets.

### 5. Add SwiftPM products

Add package products to targets:

- `Runner`: `flutter-vless`
- `XrayTunnel`: `flutter-vless-tunnel-support`

The tunnel support package links `XRay`, `Tun2SocksKit`, `Tun2SocksKitC`, and
`libresolv`.

### 6. Add PacketTunnelProvider

Copy this file into your `XrayTunnel` target:

```text
example/ios/XrayTunnel/PacketTunnelProvider.swift
```

Make sure it belongs to the `XrayTunnel` target.

### 7. Initialize in Dart

Pass the base app bundle id. The plugin appends `.XrayTunnel` internally.

```dart
await flutterVless.initializeVless(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

Run on a real iPhone:

```bash
flutter run -d <your-iphone-id>
```

## CocoaPods Fallback

If you disabled SwiftPM, CocoaPods downloads the same XRay release artifact
during `pod install`.

```bash
flutter config --no-enable-swift-package-manager
cd ios
pod install
```

## Maintainers: Publish XRay

When XRay is rebuilt:

```bash
cd ios
./build_xray_ios.sh
cd ..
./tool/create_xray_ios_release.sh
```

Upload the generated artifact:

```bash
gh release upload xray-ios-v26.3.27 build/xray-ios-release/XRay.xcframework.zip \
  --repo XIIIFOX/flutter_vless \
  --clobber
```

If the script prints a new checksum, update:

```text
ios/flutter_vless/Package.swift
ios/flutter_vless.podspec
```

Before publishing:

```bash
dart pub publish --dry-run
```

The pub archive must not include `ios/XRay.xcframework`.
