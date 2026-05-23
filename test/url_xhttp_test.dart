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
    const links = [];

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
    const url = 'vless://';

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
