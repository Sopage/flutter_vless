import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/url/vless.dart';

void main() {
  test('parses XHTTP extra and defaults empty path', () {
    // This protects the parser side of the XHTTP investigation. It proves the
    // generated config contains the fields Xray expects before the iOS provider
    // applies its packet-tunnel normalization.
    const url = 'vless://';

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
    // These links were observed to connect locally but not fetch usable page
    // bytes on device. The unit test keeps their JSON shape stable while the
    // real-device smoke test remains responsible for transport success.
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
    // TCP/Reality is the currently verified good path on iPhone. Keep this
    // parser case explicit so later XHTTP work does not regress the working
    // transport while changing shared stream settings.
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
