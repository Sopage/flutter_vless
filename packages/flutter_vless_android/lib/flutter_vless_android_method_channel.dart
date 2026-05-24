import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_vless_android_platform_interface.dart';

/// An implementation of [FlutterVlessAndroidPlatform] that uses method channels.
class MethodChannelFlutterVlessAndroid extends FlutterVlessAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_vless_android');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
