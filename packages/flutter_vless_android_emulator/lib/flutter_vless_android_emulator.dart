// Copyright (c) 2024-2026 13FOX Studio / tfox.dev.
// SPDX-License-Identifier: MIT

import 'flutter_vless_android_emulator_platform_interface.dart';

class FlutterVlessAndroidEmulator {
  Future<String?> getPlatformVersion() {
    return FlutterVlessAndroidEmulatorPlatform.instance.getPlatformVersion();
  }
}
