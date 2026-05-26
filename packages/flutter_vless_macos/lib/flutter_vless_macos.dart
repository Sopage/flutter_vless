// Copyright (c) 2024-2026 13FOX Studio / tfox.dev.
// SPDX-License-Identifier: MIT

import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';

/// macOS implementation of [VlessPlatform] using MethodChannel.
class FlutterVlessMacos extends VlessMethodChannelAdapter {
  /// Registers this class as the platform implementation.
  static void registerWith() {
    VlessPlatform.instance = FlutterVlessMacos();
  }
}
