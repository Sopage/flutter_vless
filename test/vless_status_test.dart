import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';

void main() {
  group('P0 VlessStatus parsing', () {
    test('parses the legacy EventChannel list payload safely', () {
      final status = VlessStatus.fromEvent(
        ['10', 20, '30', '40', 50, 'CONNECTED'],
      );

      expect(status.duration, 10);
      expect(status.uploadSpeed, 20);
      expect(status.downloadSpeed, 30);
      expect(status.upload, 40);
      expect(status.download, 50);
      expect(status.state, 'CONNECTED');
      expect(status.connectionState, VlessConnectionState.connected);
      expect(status.toMap(), {
        'duration': 10,
        'uploadSpeed': 20,
        'downloadSpeed': 30,
        'upload': 40,
        'download': 50,
        'state': 'CONNECTED',
      });
    });

    test('defaults missing or malformed list fields instead of throwing', () {
      final status = VlessStatus.fromEvent(['bad-number']);

      expect(status.duration, 0);
      expect(status.uploadSpeed, 0);
      expect(status.downloadSpeed, 0);
      expect(status.upload, 0);
      expect(status.download, 0);
      expect(status.state, 'DISCONNECTED');
      expect(status.connectionState, VlessConnectionState.disconnected);
    });

    test('parses map payloads with camelCase or snake_case keys', () {
      final status = VlessStatus.fromEvent({
        'duration': 7,
        'upload_speed': '8',
        'downloadSpeed': 9.7,
        'upload': '10',
        'download': 11,
        'state': 'CONNECTING',
      });

      expect(status, const TypeMatcher<VlessStatus>());
      expect(status.uploadSpeed, 8);
      expect(status.downloadSpeed, 9);
      expect(status.connectionState, VlessConnectionState.connecting);
      expect(status, VlessStatus.fromMap(status.toMap()));
    });

    test('tryParse ignores unsupported payload shapes', () {
      expect(VlessStatus.tryParse('CONNECTED'), isNull);
    });
  });
}
