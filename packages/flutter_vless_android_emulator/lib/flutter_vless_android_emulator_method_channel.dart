import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_vless_android_emulator_platform_interface.dart';

/// An implementation of [FlutterVlessAndroidEmulatorPlatform] that uses method channels.
class MethodChannelFlutterVlessAndroidEmulator
    extends FlutterVlessAndroidEmulatorPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_vless_android_emulator');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
