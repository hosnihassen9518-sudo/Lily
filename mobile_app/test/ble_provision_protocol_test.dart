import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lily_mobile/services/ble_provision_protocol.dart';

void main() {
  test('UTF-8 and escaped credentials survive smallest MTU chunking', () {
    final bytes = BleProvisionProtocol.encodeProvision(
      requestId: 'abc',
      ssid: 'Maison-é"',
      password: 'secret\\123',
      token: 'token',
    );
    for (final size in [20, 244]) {
      final chunks = BleProvisionProtocol.chunkMessage(bytes, size);
      expect(chunks.every((c) => c.length <= size), isTrue);
      final decoded =
          jsonDecode(utf8.decode(chunks.expand((c) => c).toList()).trim());
      expect(decoded['ssid'], 'Maison-é"');
      expect(decoded['password'], 'secret\\123');
      expect(decoded['version'], 1);
    }
  });
  test('Rejects invalid byte lengths and missing token', () {
    for (final ssid in ['', List.filled(17, 'é').join()]) {
      expect(
          () => BleProvisionProtocol.encodeProvision(
              requestId: '1', ssid: ssid, password: '', token: 't'),
          throwsFormatException);
    }
    expect(
        () => BleProvisionProtocol.encodeProvision(
            requestId: '1', ssid: 'home', password: 'short', token: 't'),
        throwsFormatException);
    expect(
        () => BleProvisionProtocol.encodeProvision(
            requestId: '1', ssid: 'home', password: '', token: ''),
        throwsFormatException);
    expect(
        () => BleProvisionProtocol.encodeProvision(
            requestId: '1',
            ssid: 'home',
            password: '',
            token: List.filled(2100, 'x').join()),
        throwsFormatException);
  });
  test('Ignores another operation status and retains terminal errors', () {
    expect(
        BleProvisionProtocol.decodeStatus(
            utf8.encode('{"version":1,"request_id":"old","stage":"success"}'),
            'new'),
        isNull);
    final status = BleProvisionProtocol.decodeStatus(
        utf8.encode(
            '{"version":1,"request_id":"new","stage":"error","detail":"Wrong password"}'),
        'new');
    expect(status!['stage'], 'error');
    expect(status['detail'], 'Wrong password');
    expect(
        () => BleProvisionProtocol.decodeStatus(
            utf8.encode('{"version":2,"request_id":"new"}'), 'new'),
        throwsFormatException);
  });
}
