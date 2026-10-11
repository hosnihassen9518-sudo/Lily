import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/services/provision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wifi_iot');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method == 'forceWifiUsage' ? 'route:${call.arguments['useWifi']}' : call.method);
      return true;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('Joining the setup AP explicitly binds app traffic to Wi-Fi', () async {
    expect(await ProvisionService().connectToDeviceAp('LILY-TEST'), isTrue);
    expect(calls, containsAllInOrder(['connect', 'route:true']));
  });
  test('Cleanup restores routing before disconnecting', () async {
    await ProvisionService().disconnectFromDeviceAp();
    expect(calls, ['route:false', 'disconnect']);
  });
  test('The pairing token is fetched before leaving the backend network', () async {
    final token = await ProvisionService().connectWithPairingToken('LILY-TEST', () async {
      calls.add('backend-token');
      return 'test-token';
    });
    expect(token, 'test-token');
    expect(calls, containsAllInOrder(['backend-token', 'connect', 'route:true']));
  });
  test('A brief local endpoint timeout is retried', () async {
    var attempts = 0;
    final service = ProvisionService(client: MockClient((request) async {
      expect(request.url.toString(), 'http://192.168.4.1/info');
      attempts++;
      if (attempts == 1) throw TimeoutException('network not ready');
      return http.Response('{"serial":"LILY-TEST"}', 200);
    }));
    expect((await service.getDeviceInfo())['serial'], 'LILY-TEST');
    expect(attempts, 2);
  });
  test('An unreachable local device gives a readable error', () async {
    final service = ProvisionService(client: MockClient((request) async => throw TimeoutException('offline')));
    await expectLater(service.getDeviceInfo(), throwsA(isA<Exception>().having((error) => error.toString(), 'message', contains('192.168.4.1'))));
  });
}
