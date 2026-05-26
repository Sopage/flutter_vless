import 'vless_method_channel_adapter.dart';

/// Default MethodChannel implementation of [VlessPlatform].
/// This is used when no platform-specific implementation is registered.
class MethodChannelVlessPlatform extends VlessMethodChannelAdapter {
  MethodChannelVlessPlatform();
}
