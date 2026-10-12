import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ble_provision_protocol.dart';
import 'reactive_ble_setup_transport.dart';

class BleSetupDevice {
  const BleSetupDevice({required this.id, required this.name});
  final String id;
  final String name;
}

abstract interface class BleSetupTransport {
  bool get connected;
  Future<List<BleSetupDevice>> scan();
  Future<void> connect(BleSetupDevice device);
  Future<int> payloadSize();
  Future<List<int>> readInfo();
  Future<List<int>> readStatus();
  Future<void> write(List<int> bytes);
  Future<void> disconnect();
}

class BleProvisionService {
  BleProvisionService(
      {BleSetupTransport? transport,
      this.pollInterval = const Duration(milliseconds: 500),
      this.provisionTimeout = const Duration(seconds: 65)})
      : _transport = transport ?? ReactiveBleSetupTransport();
  final BleSetupTransport _transport;
  final Duration pollInterval;
  final Duration provisionTimeout;
  bool _disposed = false;
  bool _provisioning = false;
  int _revision = 0;
  int _payloadSize = 20;

  bool get connected => !_disposed && _transport.connected;
  void _check(int revision, {bool requireConnection = false}) {
    if (_disposed || revision != _revision) {
      throw StateError('Bluetooth setup was cancelled.');
    }
    if (requireConnection && !_transport.connected) {
      throw StateError('Bluetooth disconnected. Connect to Lily again.');
    }
  }

  Future<List<BleSetupDevice>> scanDevices() async {
    final revision = _revision;
    _check(revision);
    final devices = await _transport.scan();
    _check(revision);
    return devices;
  }

  Future<Map<String, dynamic>> connect(BleSetupDevice device) async {
    final revision = _revision;
    _check(revision);
    try {
      await _transport.connect(device);
      _check(revision, requireConnection: true);
      _payloadSize =
          await _transport.payloadSize().timeout(const Duration(seconds: 5));
      _check(revision, requireConnection: true);
      final info = BleProvisionProtocol.decodeObject(
          await _transport.readInfo().timeout(const Duration(seconds: 90)));
      _check(revision, requireConnection: true);
      if (info['serial'] is! String ||
          (info['serial'] as String).isEmpty ||
          !['test_light', 'lily_audio_light']
              .contains(info['device_type_key'])) {
        throw const FormatException(
            'This device is not compatible with Lily Bluetooth setup.');
      }
      final started = DateTime.now();
      while (true) {
        final status = BleProvisionProtocol.decodeObject(
            await _transport.readStatus().timeout(const Duration(seconds: 5)));
        _check(revision, requireConnection: true);
        if (status['authenticated'] == true) break;
        if (status['authenticated'] == null) {
          throw const FormatException(
              'Install the matching 0.7.1 BLE firmware before connecting.');
        }
        if (DateTime.now().difference(started) >= const Duration(seconds: 10)) {
          throw TimeoutException(
              'Bluetooth connected, but device authentication did not complete. Check the fixed pairing PIN.');
        }
        await Future<void>.delayed(pollInterval);
      }
      debugPrint('Lily BLE: encrypted connection authenticated and ready');
      return info;
    } catch (_) {
      await _transport.disconnect();
      rethrow;
    }
  }

  Future<void> _send(List<int> bytes, int revision) async {
    for (final chunk
        in BleProvisionProtocol.chunkMessage(bytes, _payloadSize)) {
      _check(revision, requireConnection: true);
      try {
        await _transport.write(chunk).timeout(const Duration(seconds: 10));
      } catch (error) {
        debugPrint('Lily BLE: command write failed: $error');
        // A partial message must not be appended to on a later retry.
        await disconnect();
        throw StateError(
            'Bluetooth transfer failed. Reconnect Lily and retry. If Android reports GATT 133, forget the old Lily bond in Bluetooth settings and pair again using the fixed device PIN.');
      }
      _check(revision, requireConnection: true);
    }
  }

  Future<List<Map<String, dynamic>>> scanHomeNetworks() async {
    final revision = _revision;
    _check(revision, requireConnection: true);
    if (_provisioning) throw StateError('Wait for the current setup request.');
    _provisioning = true;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final unique = <String, Map<String, dynamic>>{};
    try {
      var pages = 1;
      for (var page = 0; page < pages; page++) {
        await _send(
            BleProvisionProtocol.encodeCommand({
              'version': 1,
              'request_id': id,
              'command': page == 0 ? 'scan' : 'networks',
              'page': page
            }),
            revision);
        final started = DateTime.now();
        Map<String, dynamic>? result;
        while (
            DateTime.now().difference(started) < const Duration(seconds: 25)) {
          _check(revision, requireConnection: true);
          final status = BleProvisionProtocol.decodeStatus(
              await _transport
                  .readStatus()
                  .timeout(const Duration(seconds: 10)),
              id);
          _check(revision, requireConnection: true);
          if (status?['stage'] == 'error') {
            throw StateError(
                status?['detail']?.toString() ?? 'Wi-Fi scan failed.');
          }
          if (status?['stage'] == 'wifi_networks' && status?['page'] == page) {
            result = status;
            break;
          }
          await Future<void>.delayed(pollInterval);
        }
        if (result == null) {
          throw TimeoutException(
              'The ESP32 Wi-Fi scan did not finish. Try scanning again.');
        }
        final total = result['total_pages'];
        if (total is! int ||
            total < 1 ||
            total > 64 ||
            result['networks'] is! List) {
          throw const FormatException('Invalid Wi-Fi scan response.');
        }
        pages = total;
        for (final raw in result['networks'] as List) {
          if (raw is! Map ||
              raw['ssid'] is! String ||
              raw['rssi'] is! int ||
              raw['secure'] is! bool) {
            throw const FormatException('Invalid Wi-Fi network entry.');
          }
          final network = Map<String, dynamic>.from(raw);
          final ssid = network['ssid'] as String;
          final previous = unique[ssid];
          if (ssid.isNotEmpty &&
              (previous == null ||
                  (network['rssi'] as int) > (previous['rssi'] as int))) {
            unique[ssid] = network;
          }
        }
      }
      return unique.values.toList()
        ..sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
    } finally {
      _provisioning = false;
    }
  }

  Future<void> provision(
      {required String ssid,
      required String password,
      required Future<String> Function() createToken,
      required void Function(String) onProgress}) async {
    final revision = _revision;
    _check(revision, requireConnection: true);
    if (_provisioning) throw StateError('A setup request is already running.');
    BleProvisionProtocol.validateCredentials(ssid, password);
    _provisioning = true;
    try {
      final token = await createToken().timeout(const Duration(seconds: 10));
      _check(revision, requireConnection: true);
      final requestId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      await _send(
          BleProvisionProtocol.encodeProvision(
              requestId: requestId,
              ssid: ssid,
              password: password,
              token: token),
          revision);
      final started = DateTime.now();
      String? lastStage;
      while (DateTime.now().difference(started) < provisionTimeout) {
        _check(revision, requireConnection: true);
        final status = BleProvisionProtocol.decodeStatus(
            await _transport.readStatus().timeout(const Duration(seconds: 10)),
            requestId);
        _check(revision, requireConnection: true);
        if (status != null) {
          final stage = status['stage']?.toString() ?? '';
          if (stage != lastStage) {
            lastStage = stage;
            onProgress(stage);
          }
          if (stage == 'error') {
            throw StateError(
                status['detail']?.toString() ?? 'Device setup failed.');
          }
          if (stage == 'success') {
            // Success is established before acknowledgment, which is best effort.
            try {
              await _send(
                  BleProvisionProtocol.encodeCommand({
                    'version': 1,
                    'request_id': requestId,
                    'command': 'ack'
                  }),
                  revision);
            } catch (_) {}
            return;
          }
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException(
          'Lily did not finish setup. Reconnect over Bluetooth to check or retry.');
    } finally {
      _provisioning = false;
    }
  }

  Future<void> disconnect() async {
    _revision++;
    await _transport.disconnect();
  }

  Future<Map<String, dynamic>> readManagementInfo() async {
    final revision = _revision;
    _check(revision, requireConnection: true);
    final info = BleProvisionProtocol.decodeObject(
        await _transport.readInfo().timeout(const Duration(seconds: 10)));
    _check(revision, requireConnection: true);
    if (info['management'] != true) {
      throw StateError(
          'Install compatible 0.8.0 firmware to manage Wi-Fi and reset.');
    }
    return info;
  }

  Future<Map<String, dynamic>> runManagementCommand(
      String command, Map<String, dynamic> fields) async {
    final revision = _revision;
    _check(revision, requireConnection: true);
    if (_provisioning) throw StateError('Wait for the current device request.');
    _provisioning = true;
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      await _send(
          BleProvisionProtocol.encodeCommand(
              {...fields, 'version': 1, 'request_id': id, 'command': command}),
          revision);
      final started = DateTime.now();
      while (DateTime.now().difference(started) < provisionTimeout) {
        _check(revision, requireConnection: true);
        final status = BleProvisionProtocol.decodeStatus(
            await _transport.readStatus().timeout(const Duration(seconds: 10)),
            id);
        if (status?['stage'] == 'error') {
          throw StateError(
              status?['detail']?.toString() ?? 'Device operation failed.');
        }
        if (status?['stage'] == 'success' ||
            status?['stage'] == 'reset_complete') {
          return status!;
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException(
          'Device did not confirm the operation. Reconnect and check progress.');
    } finally {
      _provisioning = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
  }
}
