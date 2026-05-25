import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';

/// Windows implementation of [VlessPlatform] using MethodChannel.
class FlutterVlessWindows extends VlessMethodChannelAdapter {
  /// Registers this class as the platform implementation.
  static void registerWith() {
    VlessPlatform.instance = FlutterVlessWindows();
  }
}
