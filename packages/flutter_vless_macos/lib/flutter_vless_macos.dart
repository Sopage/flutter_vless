import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';

/// macOS implementation of [VlessPlatform] using MethodChannel.
class FlutterVlessMacos extends VlessMethodChannelAdapter {
  /// Registers this class as the platform implementation.
  static void registerWith() {
    VlessPlatform.instance = FlutterVlessMacos();
  }
}
