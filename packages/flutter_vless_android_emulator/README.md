# flutter_vless_android_emulator

This package contains the x86_64 and x86 binaries for older `flutter_vless` Android release trains.

## Usage

Current `flutter_vless_android` releases use the main Maven Central runtime AAR for device and emulator ABIs, so new apps should not need this package. Keep it only for older versions that did not include x86/x86_64 in the main runtime AAR.

```yaml
dependencies:
  flutter_vless: ^x.y.z
  flutter_vless_android_emulator: ^x.y.z
```
