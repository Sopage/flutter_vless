import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'xray_config_test_utils.dart';

const visionSeedEncryption =
    'mlkem768x25519plus.native.1rtt.100-500-2000.75-0-100.80-0-5000.gtmOXB2AN_r905czmOIr6dKq_YDdEJB8RWGqfsXurns';

void main() {
  group('P0 subscription imports', () {
    test('imports base64 share-link lists without dropping VLESS Encryption',
        () {
      final subscription = base64Encode(utf8.encode([
        'vless://b94da146-a56e-49d7-af4c-a68c9065cbfd@example.com:2043?type=xhttp&host=s3.storage.selcloud.ru&path=/my-bucket&mode=stream-up&security=none&encryption=$visionSeedEncryption#XHTTP',
        'ss://YWVzLTEyOC1nY206cGFzcw@example.org:8388#SS',
      ].join('\n')));

      final profiles = FlutterVless.parseMany(subscription);
      final xhttpConfig = decodedConfig(profiles.first);
      final ssConfig = decodedConfig(profiles.last);

      expect(profiles, hasLength(2));
      expect(firstVnextUser(xhttpConfig)['encryption'], visionSeedEncryption);
      expect(streamSettings(xhttpConfig)['network'], 'xhttp');
      expect(proxyOutbound(ssConfig)['protocol'], 'shadowsocks');
    });

    test('imports Clash YAML VLESS XHTTP/none profiles', () {
      final profiles = FlutterVless.parseMany('''
proxies:
  - name: Clash XHTTP
    type: vless
    server: clash.example.com
    port: 2043
    uuid: b94da146-a56e-49d7-af4c-a68c9065cbfd
    network: xhttp
    security: none
    encryption: $visionSeedEncryption
    xhttp-opts:
      host: s3.storage.selcloud.ru
      path: /my-bucket
      mode: stream-up
  - name: Unsupported Hysteria
    type: hysteria2
    server: ignored.example.com
    port: 443
''');
      final config = decodedConfig(profiles.single);
      final xhttp =
          streamSettings(config)['xhttpSettings'] as Map<String, dynamic>;

      expect(firstVnextUser(config)['encryption'], visionSeedEncryption);
      expect(xhttp['host'], 's3.storage.selcloud.ru');
      expect(xhttp['path'], '/my-bucket');
      expect(xhttp['mode'], 'stream-up');
    });

    test('imports sing-box JSON VLESS and skips non-Xray-only outbounds', () {
      final profiles = FlutterVless.parseMany(jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'proxy',
            'outbounds': ['xhttp']
          },
          {
            'type': 'vless',
            'tag': 'xhttp',
            'server': 'sing-box.example.com',
            'server_port': 2043,
            'uuid': 'b94da146-a56e-49d7-af4c-a68c9065cbfd',
            'encryption': visionSeedEncryption,
            'transport': {
              'type': 'xhttp',
              'host': 's3.storage.selcloud.ru',
              'path': '/my-bucket',
              'mode': 'stream-up',
            },
            'tls': {'enabled': false}
          },
          {
            'type': 'hysteria2',
            'tag': 'unsupported',
            'server': 'ignored.example.com',
            'server_port': 443,
          },
        ]
      }));
      final config = decodedConfig(profiles.single);

      expect(firstVnextUser(config)['encryption'], visionSeedEncryption);
      expect(streamSettings(config)['security'], 'none');
      expect(streamSettings(config)['network'], 'xhttp');
    });

    test('imports sing-box JSON Shadowsocks outbounds', () {
      final profiles = FlutterVless.parseMany(jsonEncode({
        'outbounds': [
          {
            'type': 'shadowsocks',
            'tag': 'ss',
            'server': 'ss.example.com',
            'server_port': 8388,
            'method': '2022-blake3-aes-128-gcm',
            'password': 'secret',
          }
        ]
      }));
      final outbound = proxyOutbound(decodedConfig(profiles.single));
      final server = (outbound['settings'] as Map<String, dynamic>)['servers']
          [0] as Map<String, dynamic>;

      expect(outbound['protocol'], 'shadowsocks');
      expect(server['address'], 'ss.example.com');
      expect(server['method'], '2022-blake3-aes-128-gcm');
      expect(server['password'], 'secret');
    });
  });
}
