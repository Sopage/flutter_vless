import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_vless_android_emulator_method_channel.dart';

abstract class FlutterVlessAndroidEmulatorPlatform extends PlatformInterface {
  /// Constructs a FlutterVlessAndroidEmulatorPlatform.
  FlutterVlessAndroidEmulatorPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterVlessAndroidEmulatorPlatform _instance =
      MethodChannelFlutterVlessAndroidEmulator();

  /// The default instance of [FlutterVlessAndroidEmulatorPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterVlessAndroidEmulator].
  static FlutterVlessAndroidEmulatorPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterVlessAndroidEmulatorPlatform] when
  /// they register themselves.
  static set instance(FlutterVlessAndroidEmulatorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
