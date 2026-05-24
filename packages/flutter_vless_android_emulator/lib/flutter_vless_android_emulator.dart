import 'flutter_vless_android_emulator_platform_interface.dart';

class FlutterVlessAndroidEmulator {
  Future<String?> getPlatformVersion() {
    return FlutterVlessAndroidEmulatorPlatform.instance.getPlatformVersion();
  }
}
