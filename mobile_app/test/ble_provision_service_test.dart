import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lily_mobile/services/ble_provision_service.dart';

class FakeTransport implements BleSetupTransport {
  final writes = <int>[];
  @override
  bool connected = false;
  bool deny = false;
  String stage = 'success';
  bool staleFirst = false;
  int reads = 0;
  final events = <String>[];
  @override
  Future<List<BleSetupDevice>> scan() async {
    if (deny) throw StateError('Bluetooth permission denied');
    return [const BleSetupDevice(id: 'test', name: 'LILY-test')];
  }

  @override
  Future<void> connect(BleSetupDevice device) async {
    connected = true;
  }

  @override
  Future<int> payloadSize() async => 20;
  @override
  Future<List<int>> readInfo() async => utf8
      .encode('{"version":1,"serial":"test","device_type_key":"test_light"}');
  @override
  Future<List<int>> readStatus() async {
    if (writes.isEmpty) {
      return utf8.encode(
          '{"version":1,"request_id":"","stage":"ready","authenticated":true}');
    }
    reads++;
    final command = utf8.decode(writes).trim().split('\n').map(jsonDecode).last;
    if (command['command'] == 'scan' || command['command'] == 'networks') {
      final page = command['page'] ?? 0;
      return utf8.encode(jsonEncode({
        'version': 1,
        'request_id': command['request_id'],
        'stage': 'wifi_networks',
        'page': page,
        'total_pages': 2,
        'networks': page == 0
            ? [
                {'ssid': 'home', 'rssi': -65, 'secure': true}
              ]
            : [
                {'ssid': 'home', 'rssi': -40, 'secure': true},
                {'ssid': 'guest', 'rssi': -70, 'secure': false}
              ]
      }));
    }
    return utf8.encode(jsonEncode({
      'version': 1,
      'request_id': staleFirst && reads == 1 ? 'old' : command['request_id'],
      'stage': stage,
      'detail': 'Wrong password'
    }));
  }

  @override
  Future<void> write(List<int> bytes) async {
    events.add('write');
    writes.addAll(bytes);
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }
}

class AwaitingAuthentication extends FakeTransport {
  final reading = Completer<void>();
  final ready = Completer<List<int>>();
  @override
  Future<List<int>> readStatus() async {
    if (!reading.isCompleted) reading.complete();
    return ready.future;
  }
}

class FailedWrite extends FakeTransport {
  @override
  Future<void> write(List<int> bytes) async =>
      throw StateError('GATT_ERROR status 133');
}

void main() {
  test('GATT write failure disconnects instead of appending to a partial retry',
      () async {
    final transport = FailedWrite();
    final service = BleProvisionService(transport: transport);
    await service.connect(const BleSetupDevice(id: 'test', name: 'LILY-test'));
    await expectLater(
        service.provision(
            ssid: 'home',
            password: '',
            createToken: () async => 't',
            onProgress: (_) {}),
        throwsA(
            predicate((error) => error.toString().contains('Reconnect Lily'))));
    expect(transport.connected, isFalse);
    await expectLater(
        service.provision(
            ssid: 'home',
            password: '',
            createToken: () async => 't',
            onProgress: (_) {}),
        throwsStateError);
    await service.dispose();
  });
  test('Does not expose a connected device until authenticated status is ready',
      () async {
    final transport = AwaitingAuthentication();
    final service =
        BleProvisionService(transport: transport, pollInterval: Duration.zero);
    var finished = false;
    final connection = service
        .connect(const BleSetupDevice(id: 'test', name: 'LILY-test'))
        .then((_) => finished = true);
    await transport.reading.future.timeout(const Duration(milliseconds: 200));
    expect(finished, isFalse);
    transport.ready.complete(utf8.encode(
        '{"version":1,"request_id":"","stage":"ready","authenticated":true}'));
    await connection;
    expect(finished, isTrue);
    await service.dispose();
  });
  test('Fetches all ESP32 Wi-Fi scan pages and selects strongest duplicate',
      () async {
    final transport = FakeTransport();
    final service =
        BleProvisionService(transport: transport, pollInterval: Duration.zero);
    await service.connect(const BleSetupDevice(id: 'test', name: 'LILY-test'));
    final networks = await service.scanHomeNetworks();
    expect(networks.map((n) => n['ssid']), ['home', 'guest']);
    expect(networks.first['rssi'], -40);
    final messages = utf8
        .decode(transport.writes)
        .trim()
        .split('\n')
        .map(jsonDecode)
        .toList();
    expect(messages.map((m) => m['command']), ['scan', 'networks']);
    await service.dispose();
  });
  test(
      'Fetches token immediately before ordered credential chunks and ignores old status',
      () async {
    final transport = FakeTransport()..staleFirst = true;
    final service =
        BleProvisionService(transport: transport, pollInterval: Duration.zero);
    await service.connect(const BleSetupDevice(id: 'test', name: 'LILY-test'));
    await service.provision(
        ssid: 'home',
        password: 'password',
        createToken: () async {
          transport.events.add('token');
          return 'token';
        },
        onProgress: (_) {});
    expect(transport.events.first, 'token');
    final messages = utf8
        .decode(transport.writes)
        .trim()
        .split('\n')
        .map(jsonDecode)
        .toList();
    expect(messages.first['ssid'], 'home');
    expect(messages.first['pairing_token'], 'token');
    expect(messages.last['command'], 'ack');
    expect(transport.reads, 2);
    await service.dispose();
  });
  test('Backend token failure never transfers credentials', () async {
    final transport = FakeTransport();
    final service = BleProvisionService(transport: transport);
    await service.connect(const BleSetupDevice(id: 'test', name: 'LILY-test'));
    await expectLater(
        service.provision(
            ssid: 'home',
            password: '',
            createToken: () async => throw StateError('backend offline'),
            onProgress: (_) {}),
        throwsStateError);
    expect(transport.writes, isEmpty);
    await service.dispose();
  });
  test('Reports terminal device errors and bounds missing status', () async {
    final transport = FakeTransport()..stage = 'error';
    final service = BleProvisionService(
        transport: transport,
        pollInterval: Duration.zero,
        provisionTimeout: const Duration(milliseconds: 10));
    await service.connect(const BleSetupDevice(id: 'test', name: 'LILY-test'));
    await expectLater(
        service.provision(
            ssid: 'home',
            password: '',
            createToken: () async => 't',
            onProgress: (_) {}),
        throwsA(predicate((e) => e.toString().contains('Wrong password'))));
    transport.writes.clear();
    transport.stage = 'connecting_wifi';
    await expectLater(
        service.provision(
            ssid: 'home',
            password: '',
            createToken: () async => 't',
            onProgress: (_) {}),
        throwsA(isA<TimeoutException>()));
    await service.dispose();
  });
  test('Disposal while backend token is pending cancels credential transfer',
      () async {
    final transport = FakeTransport();
    final service = BleProvisionService(transport: transport);
    await service.connect(const BleSetupDevice(id: 'test', name: 'LILY-test'));
    final token = Completer<String>();
    final result = service.provision(
        ssid: 'home',
        password: '',
        createToken: () => token.future,
        onProgress: (_) {});
    final expectation = expectLater(result, throwsStateError);
    await service.dispose();
    token.complete('t');
    await expectation;
    expect(transport.writes, isEmpty);
    expect(transport.connected, isFalse);
  });
  test('Permission errors are exposed to the caller for rescan', () async {
    final transport = FakeTransport()..deny = true;
    final service = BleProvisionService(transport: transport);
    await expectLater(service.scanDevices(), throwsStateError);
    transport.deny = false;
    expect(await service.scanDevices(), hasLength(1));
    await service.dispose();
  });
}
