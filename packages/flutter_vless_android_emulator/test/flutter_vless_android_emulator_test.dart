import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless_android_emulator/flutter_vless_android_emulator.dart';
import 'package:flutter_vless_android_emulator/flutter_vless_android_emulator_platform_interface.dart';
import 'package:flutter_vless_android_emulator/flutter_vless_android_emulator_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterVlessAndroidEmulatorPlatform
    with MockPlatformInterfaceMixin
    implements FlutterVlessAndroidEmulatorPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterVlessAndroidEmulatorPlatform initialPlatform =
      FlutterVlessAndroidEmulatorPlatform.instance;

  test('$MethodChannelFlutterVlessAndroidEmulator is the default instance', () {
    expect(initialPlatform,
        isInstanceOf<MethodChannelFlutterVlessAndroidEmulator>());
  });

  test('getPlatformVersion', () async {
    FlutterVlessAndroidEmulator flutterVlessAndroidEmulatorPlugin =
        FlutterVlessAndroidEmulator();
    MockFlutterVlessAndroidEmulatorPlatform fakePlatform =
        MockFlutterVlessAndroidEmulatorPlatform();
    FlutterVlessAndroidEmulatorPlatform.instance = fakePlatform;

    expect(await flutterVlessAndroidEmulatorPlugin.getPlatformVersion(), '42');
  });
}
