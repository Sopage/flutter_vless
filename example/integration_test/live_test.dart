import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const vless1 = 'vless://6fa7944d-1b22-412b-b766-6dc073b0240b@sa-fc513ff2081d19e5.sr-4e36bf21eacf0b90.r.vpvpn.club:443?type=xhttp&host=&path=&mode=auto&extra=%257B%250A%2520%2520%2522noGRPCHeader%2522%2520:%2520false,%250A%2520%2520%2522scMaxConcurrentPosts%2522%2520:%2520100,%250A%2520%2520%2522scMaxEachPostBytes%2522%2520:%25201000000,%250A%2520%2520%2522scMinPostsIntervalMs%2522%2520:%252030,%250A%2520%2520%2522xPaddingBytes%2522%2520:%2520%2522100-1000%2522%250A%257D&security=reality&fp=chrome&sni=sentry.allepal.ee&pbk=XBBVeMURFu7jmYJ9MZwjEWgfQlGTnRs0B5So5Fy7jWs&sid=a3f9c2d4e8b1a7c6#VP%20Forward%20focus%202';
  const vless2 = 'vless://6fa7944d-1b22-412b-b766-6dc073b0240b@sa-40873beb386c2bab.sr-fd0662c478fdd423.r.vpvpn.club:443?type=xhttp&host=&path=/&mode=stream-one&extra=%257B%250A%2520%2520%2522xmux%2522%2520:%2520%257B%250A%2520%2520%2520%2520%2522maxConnections%2522%2520:%25201,%250A%2520%2520%2520%2520%2522maxReuseTimes%2522%2520:%25200%250A%2520%2520%257D%250A%257D&security=tls&sni=6fa7944d.ferrin.uk&alpn=h2&fp=chrome&allowInsecure=0#VP%20Forward%20focus%E3%80%BD';
  const vless3 = 'vless://6fa7944d-1b22-412b-b766-6dc073b0240b@sa-92cab24c2dec9fd7.sr-eafa7d0213b81797.r.vpvpn.club:443?type=xhttp&host=&path=&mode=auto&extra=%257B%250A%2520%2520%2522noGRPCHeader%2522%2520:%2520false,%250A%2520%2520%2522scMaxConcurrentPosts%2522%2520:%2520100,%250A%2520%2520%2522scMaxEachPostBytes%2522%2520:%25201000000,%250A%2520%2520%2522scMinPostsIntervalMs%2522%2520:%252030,%250A%2520%2520%2522xPaddingBytes%2522%2520:%2520%2522100-1000%2522%250A%257D&security=reality&fp=qq&sni=stats.vk-portal.net&pbk=XBBVeMURFu7jmYJ9MZwjEWgfQlGTnRs0B5So5Fy7jWs&sid=992f3294e2336744#%F0%9F%87%A9%F0%9F%87%AAVP%20%D0%93%D0%B5%D1%80%D0%BC%D0%B0%D0%BD%D0%B8%D1%8F';

  final xrayJson = {
    "dns" : {
      "queryStrategy" : "UseIPv4"
    },
    "inbounds" : [
      {
        "listen" : "127.0.0.1",
        "port" : 10808,
        "protocol" : "socks",
        "settings" : {
          "auth" : "noauth",
          "udp" : true
        },
        "sniffing" : {
          "destOverride" : [
            "quic",
            "tls",
            "http"
          ],
          "enabled" : true,
          "excludedDomains" : [

          ],
          "metadataOnly" : false,
          "routeOnly" : true
        },
        "tag" : "socks-in"
      },
      {
        "listen" : "127.0.0.1",
        "port" : 10820,
        "protocol" : "socks",
        "settings" : {
          "auth" : "noauth",
          "udp" : true
        },
        "sniffing" : {
          "destOverride" : [
            "quic",
            "tls",
            "http"
          ],
          "enabled" : true,
          "excludedDomains" : [

          ],
          "metadataOnly" : false,
          "routeOnly" : true
        },
        "tag" : "socks-direct"
      }
    ],
    "log" : {
      "loglevel" : "Warning"
    },
    "outbounds" : [
      {
        "protocol" : "vless",
        "settings" : {
          "testpre" : null,
          "testseed" : null,
          "vnext" : [
            {
              "address" : "sa-781417d2850f8693.sr-b109dc0322c2e349.r.vpvpn.club",
              "port" : 443,
              "users" : [
                {
                  "encryption" : "none",
                  "flow" : "xtls-rprx-vision",
                  "id" : "85fede74-c172-4595-8208-82a86c45cc80",
                  "level" : 8,
                  "security" : "auto"
                }
              ]
            }
          ]
        },
        "streamSettings" : {
          "isCustomFinalmask" : false,
          "network" : "tcp",
          "realitySettings" : {
            "fingerprint" : "chrome",
            "publicKey" : "Saqm-pfkT3zPx5mmT7UPg2ieUOU6ja--k3ivXGHG_Ws",
            "serverName" : "www.samsung.com",
            "shortId" : "0e903b415d812c59",
            "show" : false,
            "spiderX" : "/"
          },
          "security" : "reality",
          "tcpSettings" : {
            "header" : {
              "type" : "none"
            }
          }
        },
        "tag" : "proxy"
      },
      {
        "protocol" : "freedom",
        "tag" : "direct"
      },
      {
        "protocol" : "blackhole",
        "tag" : "block"
      }
    ],
    "policy" : {
      "levels" : {
        "8" : {
          "bufferSize" : 3,
          "connIdle" : 300,
          "downlinkOnly" : 4,
          "handshake" : 3,
          "uplinkOnly" : 2
        }
      },
      "system" : {

      }
    },
    "remarks" : "🇺🇸VP  США (WiFi) #3",
    "routing" : {
      "domainStrategy" : "AsIs",
      "rules" : [
        {
          "inboundTag" : [
            "socks-direct"
          ],
          "outboundTag" : "direct"
        }
      ]
    }
  };

  testWidgets('macOS Live Test using Real Configuration Data', (tester) async {
    // 1. Setup Status Listener
    final statuses = <VlessStatus>[];
    final vless = FlutterVless(
      onStatusChanged: (status) {
        statuses.add(status);
        debugPrint(
          '[LIVE_TEST_OUT] Status Updated -> state=${status.state} '
          'upSpeed=${status.uploadSpeed} B/s, downSpeed=${status.downloadSpeed} B/s, '
          'totalUp=${status.upload} B, totalDown=${status.download} B, '
          'duration=${status.duration}s',
        );
      },
    );

    // 2. Initialize Vless
    debugPrint('[LIVE_TEST_OUT] Initializing FlutterVless...');
    await vless.initializeVless();
    final coreVersion = await vless.getCoreVersion();
    debugPrint('[LIVE_TEST_OUT] Xray Core Version: $coreVersion');
    expect(coreVersion, isNotEmpty);

    // 3. Test `getServerDelay` on all 3 links
    final configs = [vless1, vless2, vless3];
    for (int i = 0; i < configs.length; i++) {
      final parsed = FlutterVless.parse(configs[i]);
      final configJson = parsed.getFullConfiguration();
      debugPrint('[LIVE_TEST_OUT] Measuring delay for Config ${i + 1} (${parsed.remark})...');
      try {
        final delay = await vless.getServerDelay(config: configJson);
        debugPrint('[LIVE_TEST_OUT] Config ${i + 1} Delay: ${delay}ms');
      } catch (e) {
        debugPrint('[LIVE_TEST_OUT] Config ${i + 1} Delay measurement failed: $e');
      }
    }

    // 4. Test SOCKS Proxy Connection for Config 1
    final parsedConfig1 = FlutterVless.parse(vless1);
    final config1Json = parsedConfig1.getFullConfiguration();
    debugPrint('[LIVE_TEST_OUT] Starting connection for Config 1 (Proxy mode)...');
    
    await vless.startVless(
      remark: parsedConfig1.remark,
      config: config1Json,
      proxyOnly: true,
    );

    debugPrint('[LIVE_TEST_OUT] Connected! Waiting 6 seconds for status updates...');
    await Future<void>.delayed(const Duration(seconds: 6));

    debugPrint('[LIVE_TEST_OUT] Measuring connected server delay...');
    try {
      final delay = await vless.getConnectedServerDelay();
      debugPrint('[LIVE_TEST_OUT] Connected Server Delay: ${delay}ms');
    } catch (e) {
      debugPrint('[LIVE_TEST_OUT] Connected Server Delay failed: $e');
    }

    debugPrint('[LIVE_TEST_OUT] Stopping connection...');
    await vless.stopVless();
    await Future<void>.delayed(const Duration(seconds: 2));

    // 5. Test SOCKS Proxy Connection for Config 4 (JSON Config)
    final jsonConfigString = jsonEncode(xrayJson);
    debugPrint('[LIVE_TEST_OUT] Starting connection for Config 4 (Raw JSON, Proxy mode)...');
    
    await vless.startVless(
      remark: xrayJson['remarks'] as String,
      config: jsonConfigString,
      proxyOnly: true,
    );

    debugPrint('[LIVE_TEST_OUT] Connected! Waiting 6 seconds for status updates...');
    await Future<void>.delayed(const Duration(seconds: 6));

    debugPrint('[LIVE_TEST_OUT] Measuring connected server delay for Config 4...');
    try {
      final delay = await vless.getConnectedServerDelay();
      debugPrint('[LIVE_TEST_OUT] Config 4 Connected Server Delay: ${delay}ms');
    } catch (e) {
      debugPrint('[LIVE_TEST_OUT] Config 4 Connected Server Delay failed: $e');
    }

    debugPrint('[LIVE_TEST_OUT] Stopping connection for Config 4...');
    await vless.stopVless();

    debugPrint('[LIVE_TEST_OUT] macOS Live Test Completed Successfully!');
  });
}
