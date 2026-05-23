import 'dart:convert';

import 'package:flutter_vless/url/url.dart';

Map<String, dynamic> decodedConfig(FlutterVlessURL parsed) {
  return jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;
}

Map<String, dynamic> proxyOutbound(Map<String, dynamic> config) {
  return (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
}

Map<String, dynamic> streamSettings(Map<String, dynamic> config) {
  return proxyOutbound(config)['streamSettings'] as Map<String, dynamic>;
}

Map<String, dynamic> firstVnextServer(Map<String, dynamic> config) {
  final settings = proxyOutbound(config)['settings'] as Map<String, dynamic>;
  final vnext = settings['vnext'] as List<dynamic>;
  return vnext.first as Map<String, dynamic>;
}

Map<String, dynamic> firstVnextUser(Map<String, dynamic> config) {
  final users = firstVnextServer(config)['users'] as List<dynamic>;
  return users.first as Map<String, dynamic>;
}

Map<String, dynamic> firstOutboundServer(Map<String, dynamic> config) {
  final settings = proxyOutbound(config)['settings'] as Map<String, dynamic>;
  final servers = settings['servers'] as List<dynamic>;
  return servers.first as Map<String, dynamic>;
}

String base64UrlNoPadding(String value) {
  return base64UrlEncode(utf8.encode(value)).replaceAll('=', '');
}

String vmessLink(Map<String, dynamic> rawConfig) {
  return 'vmess://${base64Encode(utf8.encode(jsonEncode(rawConfig)))}';
}
