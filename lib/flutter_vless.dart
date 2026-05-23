import 'dart:convert';

import 'package:flutter_vless/url/shadowsocks.dart';
import 'package:flutter_vless/url/socks.dart';
import 'package:flutter_vless/url/trojan.dart';
import 'package:flutter_vless/url/url.dart';
import 'package:flutter_vless/url/vless.dart';
import 'package:flutter_vless/url/vmess.dart';
import 'package:flutter_vless/url/xray_config.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';

export 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';
export 'url/url.dart';

class FlutterVless {
  FlutterVless({required this.onStatusChanged});

  /// This method is called when FlutterVless status has changed.
  final void Function(VlessStatus status) onStatusChanged;

  /// Requests VPN permission from the user (Android).
  Future<bool> requestPermission() {
    return VlessPlatform.instance.requestPermission();
  }

  /// Initializes the VPN plugin with platform-specific configuration.
  Future<void> initializeVless({
    String notificationIconResourceType = "mipmap",
    String notificationIconResourceName = "ic_launcher",
    String providerBundleIdentifier = "",
    String groupIdentifier = "",
  }) async {
    await VlessPlatform.instance.initializeVless(
      onStatusChanged: onStatusChanged,
      notificationIconResourceType: notificationIconResourceType,
      notificationIconResourceName: notificationIconResourceName,
      providerBundleIdentifier: providerBundleIdentifier,
      groupIdentifier: groupIdentifier,
    );
  }

  /// Start FlutterVless service.
  ///
  /// config:
  ///
  ///   FlutterVless Config (json)
  ///
  /// blockedApps:
  ///
  ///   Apps that won't go through the VPN tunnel.
  ///
  ///   Contains a list of package names.
  ///
  ///   specifically for Android.
  ///
  ///   For iOS, please use blockedDomains instead, in example folder.
  ///
  /// bypassSubnets:
  ///
  ///     [Default = 0.0.0.0/0]
  ///
  ///     Add at least one route if you want the system to send traffic through the VPN interface.
  ///
  ///     Routes filter by destination addresses.
  ///
  ///     To accept all traffic, set an open route such as 0.0.0.0/0 or ::/0.
  ///
  /// proxyOnly:
  ///
  ///   If it is true, only the FlutterVless proxy will be executed,
  ///
  ///   and the VPN tunnel will not be executed.
  Future<void> startVless({
    required String remark,
    required String config,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    bool proxyOnly = false,
    String notificationDisconnectButtonName = "DISCONNECT",
  }) async {
    try {
      if (jsonDecode(config) == null) {
        throw ArgumentError('The provided string is not valid JSON');
      }
    } catch (_) {
      throw ArgumentError('The provided string is not valid JSON');
    }

    await VlessPlatform.instance.startVless(
      remark: remark,
      config: config,
      blockedApps: blockedApps,
      proxyOnly: proxyOnly,
      bypassSubnets: bypassSubnets,
      notificationDisconnectButtonName: notificationDisconnectButtonName,
    );
  }

  /// Stop FlutterVless service.
  Future<void> stopVless() async {
    await VlessPlatform.instance.stopVless();
  }

  /// This method returns the real server delay of the configuration.
  Future<int> getServerDelay(
      {required String config,
      String url = 'https://google.com/generate_204'}) async {
    try {
      if (jsonDecode(config) == null) {
        throw ArgumentError('The provided string is not valid JSON');
      }
    } catch (_) {
      throw ArgumentError('The provided string is not valid JSON');
    }
    return await VlessPlatform.instance
        .getServerDelay(config: config, url: url);
  }

  /// This method returns the connected server delay.
  Future<int> getConnectedServerDelay(
      {String url = 'https://google.com/generate_204'}) async {
    return await VlessPlatform.instance.getConnectedServerDelay(url);
  }

  // This method returns the FlutterVless Core version.
  Future<String> getCoreVersion() async {
    return await VlessPlatform.instance.getCoreVersion();
  }

  /// Parse a share link or raw Xray JSON config.
  ///
  /// Supports vmess://, vless://, trojan://, ss://, socks://, and JSON.
  /// Prefer this over [parseFromURL] for clipboard/subscription imports: raw
  /// JSON can carry VLESS Encryption keys that are not recoverable from a bare
  /// `vless://` link.
  static FlutterVlessURL parse(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return XrayJsonConfig(url: trimmed);
    }
    return parseFromURL(trimmed);
  }

  /// parse FlutterVlessURL object from Vless share link
  ///
  /// like vmess://, vless://, trojan://, ss://, socks://
  static FlutterVlessURL parseFromURL(String url) {
    switch (url.split("://")[0].toLowerCase()) {
      case 'vmess':
        return VmessURL(url: url);
      case 'vless':
        return VlessURL(url: url);
      case 'trojan':
        return TrojanURL(url: url);
      case 'ss':
        return ShadowSocksURL(url: url);
      case 'socks':
        return SocksURL(url: url);
      default:
        throw ArgumentError('url is invalid');
    }
  }
}
