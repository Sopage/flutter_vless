# Windows Support

This plugin now supports Windows platform in addition to Android and iOS.

## Implementation Details

The Windows implementation uses:
- C++ for native code
- Flutter's Windows plugin API
- V2ray/Xray core integration (placeholder - needs actual v2ray/xray library integration)

## Building

The Windows plugin is built automatically when you build your Flutter app for Windows:

```bash
flutter build windows
```

## Current Status

The Windows implementation provides:
- ✅ Basic plugin structure and method channel communication
- ✅ Status event streaming
- ✅ Proxy mode support (proxyOnly parameter)
- ✅ **Full Xray-core integration (version 25.10.15+)**
- ✅ Process management for xray.exe
- ✅ API client for stats and delay measurement
- ✅ Automatic Xray executable detection
- ✅ JSON configuration validation
- ✅ Traffic statistics from Xray API
- ✅ Delay measurement through Xray
- ✅ Version detection from Xray executable

## Xray Integration

The plugin now fully integrates with Xray-core for Windows:
- Automatically searches for `xray.exe` in common locations
- Launches Xray as a separate process with JSON configuration
- Communicates with Xray via HTTP API (default: `127.0.0.1:10085`)
- Monitors process health and handles cleanup
- Provides real-time traffic statistics
- Measures server delay through Xray connection

See [XRAY_SETUP.md](./windows/XRAY_SETUP.md) for detailed setup instructions.

## Modern Implementation Features

This implementation uses modern C++17/20 features:
- `std::filesystem` for cross-platform file operations
- `std::optional` for safe nullable returns
- `std::unique_ptr` and RAII for automatic resource management
- `std::atomic` for thread-safe operations
- `std::future` and `std::async` for asynchronous operations
- Smart pointers and move semantics
- Exception-safe code

## Notes

- Xray executable (xray.exe) must be available on the system
- Admin rights may be required for full VPN mode (TUN/TAP interface)
- The plugin automatically manages temporary configuration files
- API must be enabled in Xray configuration for stats and delay measurement

