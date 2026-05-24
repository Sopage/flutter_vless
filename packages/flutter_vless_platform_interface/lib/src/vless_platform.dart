import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'vless_status.dart';
import 'method_channel_vless_platform.dart';

/// The interface that platform implementations must implement.
abstract class VlessPlatform extends PlatformInterface {
  /// Constructs a VlessPlatform.
  VlessPlatform() : super(token: _token);

  static final Object _token = Object();

  static VlessPlatform _instance = MethodChannelVlessPlatform();

  /// The default instance of [VlessPlatform] to use.
  ///
  /// Defaults to [MethodChannelVlessPlatform].
  static VlessPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VlessPlatform] when
  /// they register themselves.
  static set instance(VlessPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Requests VPN permission from the user (Android).
  Future<bool> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Initializes the VPN plugin with platform-specific configuration.
  Future<void> initializeVless({
    required void Function(VlessStatus status) onStatusChanged,
    required String notificationIconResourceType,
    required String notificationIconResourceName,
    required String providerBundleIdentifier,
    required String groupIdentifier,
  }) {
    throw UnimplementedError('initializeVless() has not been implemented.');
  }

  /// Starts the VPN connection with the given configuration.
  Future<void> startVless({
    required String remark,
    required String config,
    required String notificationDisconnectButtonName,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    bool proxyOnly = false,
  }) {
    throw UnimplementedError('startVless() has not been implemented.');
  }

  /// Stops the VPN connection.
  Future<void> stopVless() {
    throw UnimplementedError('stopVless() has not been implemented.');
  }

  /// Measures delay/ping for a server configuration (when not connected).
  Future<int> getServerDelay({required String config, required String url}) {
    throw UnimplementedError('getServerDelay() has not been implemented.');
  }

  /// Measures delay/ping for the currently connected server.
  Future<int> getConnectedServerDelay(String url) {
    throw UnimplementedError(
      'getConnectedServerDelay() has not been implemented.',
    );
  }

  /// Gets the version of the underlying core (Xray).
  Future<String> getCoreVersion() {
    throw UnimplementedError(
      'getCoreVersion() has not been implemented.',
    );
  }
}
