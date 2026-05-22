import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/url/vless.dart';

void main() {
  test('parses XHTTP extra and defaults empty path', () {
    const url =
        'vless://6fa7944d-1b22-412b-b766-6dc073b0240b@sa-92cab24c2dec9fd7.sr-eafa7d0213b81797.r.vpvpn.club:443?type=xhttp&host=&path=&mode=auto&extra=%257B%250A%2520%2520%2522noGRPCHeader%2522%2520:%2520false,%250A%2520%2520%2522scMaxConcurrentPosts%2522%2520:%2520100,%250A%2520%2520%2522scMaxEachPostBytes%2522%2520:%25201000000,%250A%2520%2520%2522scMinPostsIntervalMs%2522%2520:%252030,%250A%2520%2520%2522xPaddingBytes%2522%2520:%2520%2522100-1000%2522%250A%257D&security=reality&fp=qq&sni=stats.vk-portal.net&pbk=XBBVeMURFu7jmYJ9MZwjEWgfQlGTnRs0B5So5Fy7jWs&sid=992f3294e2336744#test';

    final config = jsonDecode(VlessURL(url: url).getFullConfiguration())
        as Map<String, dynamic>;
    final inbound =
        (config['inbounds'] as List<dynamic>).first as Map<String, dynamic>;
    final routing = config['routing'] as Map<String, dynamic>;
    final outbounds = config['outbounds'] as List<dynamic>;
    final proxy = outbounds.first as Map<String, dynamic>;
    final streamSettings = proxy['streamSettings'] as Map<String, dynamic>;
    final xhttpSettings =
        streamSettings['xhttpSettings'] as Map<String, dynamic>;
    final extra = xhttpSettings['extra'] as Map<String, dynamic>;

    expect(inbound['sniffing'], {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'metadataOnly': false,
    });
    expect(config.containsKey('dns'), isFalse);
    expect(routing['domainStrategy'], 'AsIs');
    expect(xhttpSettings['path'], '/');
    expect(extra['noGRPCHeader'], isFalse);
    expect(extra['scMaxConcurrentPosts'], 100);
    expect(extra['scMaxEachPostBytes'], 1000000);
    expect(extra['scMinPostsIntervalMs'], 30);
    expect(extra['xPaddingBytes'], '100-1000');
  });

  test('parses provided XHTTP stream-up links', () {
    const links = [
      (
        url:
            'vless://b94da146-a56e-49d7-af4c-a68c9065cbfd@sa-c8d2093bf58884a3.sr-a93a7d317d02f67a.r.vpvpn.club:2043?type=xhttp&host=s3.storage.selcloud.ru&path=/my-bucket&mode=stream-up&security=none#test',
        address: 'sa-c8d2093bf58884a3.sr-a93a7d317d02f67a.r.vpvpn.club',
        port: 2043,
        host: 's3.storage.selcloud.ru',
        path: '/my-bucket',
      ),
      (
        url:
            'vless://b94da146-a56e-49d7-af4c-a68c9065cbfd@sa-8308bb77ca8c9b60.sr-1696169094d1555d.r.vpvpn.club:8008?type=xhttp&host=pcloud.com&path=/upload&mode=stream-up&security=none#test',
        address: 'sa-8308bb77ca8c9b60.sr-1696169094d1555d.r.vpvpn.club',
        port: 8008,
        host: 'pcloud.com',
        path: '/upload',
      ),
    ];

    for (final link in links) {
      final config = jsonDecode(VlessURL(url: link.url).getFullConfiguration())
          as Map<String, dynamic>;
      final proxy =
          (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
      final vnext =
          (proxy['settings'] as Map<String, dynamic>)['vnext'] as List<dynamic>;
      final server = vnext.first as Map<String, dynamic>;
      final streamSettings = proxy['streamSettings'] as Map<String, dynamic>;
      final xhttpSettings =
          streamSettings['xhttpSettings'] as Map<String, dynamic>;

      expect(server['address'], link.address);
      expect(server['port'], link.port);
      expect(streamSettings['network'], 'xhttp');
      expect(streamSettings['security'], 'none');
      expect(xhttpSettings['host'], link.host);
      expect(xhttpSettings['path'], link.path);
      expect(xhttpSettings['mode'], 'stream-up');
      expect(xhttpSettings.containsKey('extra'), isFalse);
    }
  });

  test('parses provided Reality TCP link', () {
    const url =
        'vless://da13f276-d061-4f2d-969a-ed78666b929d@sa-fce7fc3b45c84045.sr-632a4f5e2e836768.r.vpvpn.club:443?type=tcp&headerType=none&security=reality&fp=qq&sni=pl1.cowjuice.me&pbk=hyWywSIlgux05EhWlFV4QEIOYWkZK55GUuPJBMDXUW0&sid=111aaa24#test';

    final config = jsonDecode(VlessURL(url: url).getFullConfiguration())
        as Map<String, dynamic>;
    final proxy =
        (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
    final streamSettings = proxy['streamSettings'] as Map<String, dynamic>;
    final realitySettings =
        streamSettings['realitySettings'] as Map<String, dynamic>;

    expect(streamSettings['network'], 'tcp');
    expect(streamSettings['security'], 'reality');
    expect(realitySettings['serverName'], 'pl1.cowjuice.me');
    expect(realitySettings['fingerprint'], 'qq');
    expect(realitySettings['publicKey'],
        'hyWywSIlgux05EhWlFV4QEIOYWkZK55GUuPJBMDXUW0');
    expect(realitySettings['shortId'], '111aaa24');
  });
}
