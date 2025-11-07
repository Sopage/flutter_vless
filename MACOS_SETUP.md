> Use the [example/](./example/) folder to run it on macOS or follow the instructions below. If that doesn't work, try running the project from the example directory—it usually helps identify the cause of any issues.


## Installation


#### Download Xray-core

Run the download script:

```bash
./scripts/download_xray_macos.sh
```

This will:
1. Download the latest Xray-core v25.10.15+ from [official releases](https://github.com/XTLS/Xray-core/releases)
2. Extract the binary for your architecture (arm64 or x86_64)
3. Make it executable

#### Place Xray Binary

The plugin will automatically search for `xray` binary in the following locations:

1. App bundle: `Runner.app/Contents/Resources/xray`
2. Shared container: `group.dev.tfox.flutterVlessExample/xray` (for Network Extension)
3. Application Support: `~/Library/Application Support/flutter_vless/xray`
4. Home directory: `~/.flutter_vless/xray`
5. System paths: `/usr/local/bin/xray`, `/opt/homebrew/bin/xray`

**Recommended**: Copy to app bundle or Application Support:
```bash
# Option 1: App bundle (for main app)
cp build/xray-macos-bin/xray example/macos/Runner/xray

# Option 2: Application Support (system-wide)
mkdir -p ~/Library/Application\ Support/flutter_vless
cp build/xray-macos-bin/xray ~/Library/Application\ Support/flutter_vless/xray
```

**Note**: For Network Extension, the binary must be accessible from the extension's container. Use App Groups capability to share the binary. 

## Podfile
Open macos/Podfile and set the platform to macOS 11
```Podfile
# Uncomment this line to define a global platform for your project
platform :osx, '11.0'
```

```bash
cd macos/
pod install
```

## Xcode Setup

- Open Runner.xcworkspace with Xcode.

### Runner target
- Set the Minimum Deployment Target to macOS 11.0.
- Go to the Signing & Capabilities tab.
- Add the App Group capability.
- Add the Network Extension capability and activate Packet Tunnel.


### XrayTunnel target
- Add a Network Extension Target with the name __XrayTunnel__
- Set the Minimum Deployment Target to macOS 11.0.
- Add the App Group capability.
- Add the Network Extension capability and activate Packet Tunnel.

#### Add XrayTunnel dependencies
- Open the Runner project and go to the Package Dependencies tab.
- Add https://github.com/EbrahimTahernejad/Tun2SocksKit to the XrayTunnel Target.
- Open the __General__ tab of the __XrayTunnel__ Target.
- Add __libresolv.tbd__ to Frameworks and Libraries.
- **Important**: Copy the Xray binary to the XrayTunnel target's resources or shared container (see download instructions above).


<br>

- Open macos/XrayTunnel/PacketTunnelProvider.swift.
- The file is already updated to use Xray-core binary directly (v25.10.15+).
- Ensure the Xray binary is accessible from the Network Extension (see download instructions above).
- Open the Runner Target > Build Phases tab.
- Move __Embed Foundation Extensions__ to the bottom of __Copy Bundle Resources__.



## flutter
Pass the providerBundleIdentifier and groupIdentifier to the initializeVless function:

``` dart
await flutterVless.initializeVless(
    providerBundleIdentifier: "macOS Provider bundle identifier",
    groupIdentifier: "macOS Group Identifier",
);
```

