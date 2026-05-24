import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_vless_android_method_channel.dart';

abstract class FlutterVlessAndroidPlatform extends PlatformInterface {
  /// Constructs a FlutterVlessAndroidPlatform.
  FlutterVlessAndroidPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterVlessAndroidPlatform _instance =
      MethodChannelFlutterVlessAndroid();

  /// The default instance of [FlutterVlessAndroidPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterVlessAndroid].
  static FlutterVlessAndroidPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterVlessAndroidPlatform] when
  /// they register themselves.
  static set instance(FlutterVlessAndroidPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
