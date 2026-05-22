import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real device VPN provider health check', (tester) async {
    final statuses = <VlessStatus>[];
    final vless = FlutterVless(
      onStatusChanged: (status) {
        statuses.add(status);
      },
    );

    await vless.initializeVless(
      providerBundleIdentifier: 'dev.tfox.flutterXrayExample',
      groupIdentifier: 'group.dev.tfox.flutterXray',
    );

    final permissionGranted = await vless.requestPermission();
    expect(permissionGranted, isTrue);

    // Override VPN_TEST_URL when comparing transports on a real iPhone. The
    // assertions below require actual HTTP bytes through the provider, so a
    // green run means more than NEVPNStatus.connected or non-zero counters.
    const url = String.fromEnvironment(
      'VPN_TEST_URL',
      defaultValue:
          'vless://6fa7944d-1b22-412b-b766-6dc073b0240b@sa-92cab24c2dec9fd7.sr-eafa7d0213b81797.r.vpvpn.club:443?type=xhttp&host=&path=&mode=auto&extra=%257B%250A%2520%2520%2522noGRPCHeader%2522%2520:%2520false,%250A%2520%2520%2522scMaxConcurrentPosts%2522%2520:%2520100,%250A%2520%2520%2522scMaxEachPostBytes%2522%2520:%25201000000,%250A%2520%2520%2522scMinPostsIntervalMs%2522%2520:%252030,%250A%2520%2520%2522xPaddingBytes%2522%2520:%2520%2522100-1000%2522%250A%257D&security=reality&fp=qq&sni=stats.vk-portal.net&pbk=XBBVeMURFu7jmYJ9MZwjEWgfQlGTnRs0B5So5Fy7jWs&sid=992f3294e2336744#test',
    );
    final parsed = FlutterVless.parseFromURL(url);

    try {
      await vless.startVless(
        remark: parsed.remark,
        config: parsed.getFullConfiguration(),
      );

      await _waitFor(
        () =>
            statuses.any((status) => status.state.toUpperCase() == 'CONNECTED'),
        timeout: const Duration(seconds: 30),
        description: 'VPN CONNECTED status',
      );

      final delay = await vless.getConnectedServerDelay(
        url: 'https://www.gstatic.com/generate_204',
      );
      expect(delay, greaterThanOrEqualTo(0));

      await Future<void>.delayed(const Duration(seconds: 8));
      const channel = MethodChannel('flutter_vless');
      final snapshot =
          await channel.invokeMethod<String>('getProviderDebugSnapshot') ?? '';

      // ignore: avoid_print
      print('VPN_PROVIDER_DEBUG_BEGIN\n$snapshot\nVPN_PROVIDER_DEBUG_END');

      // The HTTP health-check line is the important proof: TCP/Reality passed
      // only after Xray, HEV, DNS/routing, and public Internet response all
      // worked together. XHTTP links that connect locally but cannot fetch bytes
      // fail here instead of looking like a successful VPN session.
      expect(snapshot, contains('IPv6 tunnel routing disabled'));
      expect(snapshot, contains('SOCKS inbound health check: ok'));
      expect(snapshot, contains('SOCKS CONNECT health check: ok'));
      expect(snapshot, contains('SOCKS HTTP health check: ok'));
    } finally {
      await vless.stopVless();
    }
  });
}

Future<void> _waitFor(
  bool Function() predicate, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Timed out waiting for $description');
}
