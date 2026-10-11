import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_provision_protocol.dart';
import 'ble_provision_service.dart';

class ReactiveBleSetupTransport implements BleSetupTransport {
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  Completer<List<BleSetupDevice>>? _scanResult;
  Completer<void>? _connectedResult;
  String? _deviceId;
  bool _connected = false;
  int _generation = 0;
  @override
  bool get connected => _connected;
  static final _service = Uuid.parse(BleProvisionProtocol.serviceUuid);

  void _check(int generation) {
    if (generation != _generation) {
      throw StateError('Bluetooth setup was cancelled.');
    }
  }

  Future<void> _prepare(int generation) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError(
          'Bluetooth setup is available on Android and iOS.');
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final sdk = await const MethodChannel('lily/platform')
              .invokeMethod<int>('androidSdk') ??
          31;
      _check(generation);
      final permissions = sdk >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final statuses = await permissions.request();
      _check(generation);
      if (statuses.values.any((s) => !s.isGranted)) {
        throw StateError(
            'Allow Nearby devices${sdk < 31 ? ' / Location' : ''} permission in app settings, then scan again.');
      }
    }
    // CoreBluetooth prompts from initialize()/statusStream on iOS.
    final status = await _ble.statusStream
        .firstWhere((s) => s != BleStatus.unknown)
        .timeout(const Duration(seconds: 5));
    _check(generation);
    if (status != BleStatus.ready) {
      throw StateError(switch (status) {
        BleStatus.poweredOff => 'Turn on Bluetooth, then scan again.',
        BleStatus.unauthorized =>
          'Allow Bluetooth permission in app settings, then scan again.',
        BleStatus.locationServicesDisabled =>
          'Turn on Location services for Bluetooth discovery, then scan again.',
        _ => 'Bluetooth is unavailable on this phone.',
      });
    }
  }

  @override
  Future<List<BleSetupDevice>> scan() async {
    await disconnect();
    final generation = _generation;
    await _prepare(generation);
    _check(generation);
    final devices = <String, BleSetupDevice>{};
    final result = Completer<List<BleSetupDevice>>();
    _scanResult = result;
    final timer = Timer(const Duration(seconds: 10), () {
      if (!result.isCompleted) {
        result.complete(
            devices.values.toList()..sort((a, b) => a.name.compareTo(b.name)));
      }
    });
    _scan = _ble.scanForDevices(
        withServices: [_service],
        scanMode: ScanMode.lowLatency).listen((device) {
      if (generation != _generation) return;
      devices[device.id] = BleSetupDevice(
          id: device.id,
          name: device.name.isEmpty ? 'Lily (${device.id})' : device.name);
    }, onError: (Object error) {
      if (!result.isCompleted) result.completeError(error);
    });
    try {
      return await result.future;
    } finally {
      timer.cancel();
      await _scan?.cancel();
      _scan = null;
      _scanResult = null;
    }
  }

  @override
  Future<void> connect(BleSetupDevice device) async {
    await disconnect();
    final generation = _generation;
    await _prepare(generation);
    _check(generation);
    _deviceId = device.id;
    if (defaultTargetPlatform == TargetPlatform.android) {
      debugPrint('Lily BLE: waiting for Android pairing to finish');
      await const MethodChannel('lily/platform').invokeMethod<bool>(
          'ensureBonded',
          {'address': device.id}).timeout(const Duration(seconds: 95));
      _check(generation);
      debugPrint(
          'Lily BLE: Android pairing complete; establishing GATT connection');
    }
    final result = Completer<void>();
    _connectedResult = result;
    _connection = _ble.connectToDevice(
        id: device.id,
        connectionTimeout: const Duration(seconds: 20),
        servicesWithCharacteristicsToDiscover: {
          _service: [
            Uuid.parse(BleProvisionProtocol.infoUuid),
            Uuid.parse(BleProvisionProtocol.commandUuid),
            Uuid.parse(BleProvisionProtocol.statusUuid)
          ],
        }).listen((update) {
      if (generation != _generation) return;
      _connected = update.connectionState == DeviceConnectionState.connected;
      debugPrint('Lily BLE: link ${update.connectionState.name}');
      if (_connected && !result.isCompleted) result.complete();
      if (update.connectionState == DeviceConnectionState.disconnected &&
          !result.isCompleted) {
        result.completeError(StateError(
            'Could not connect over Bluetooth. Move closer to Lily and try again.'));
      }
    }, onError: (Object error) {
      _connected = false;
      if (!result.isCompleted) result.completeError(error);
    });
    try {
      await result.future.timeout(const Duration(seconds: 25));
    } catch (_) {
      await disconnect();
      rethrow;
    } finally {
      _connectedResult = null;
    }
  }

  QualifiedCharacteristic _characteristic(String uuid) {
    if (!_connected || _deviceId == null) {
      throw StateError('Bluetooth disconnected. Connect to Lily again.');
    }
    return QualifiedCharacteristic(
        serviceId: _service,
        characteristicId: Uuid.parse(uuid),
        deviceId: _deviceId!);
  }

  @override
  Future<int> payloadSize() async {
    if (_deviceId == null) return 20;
    try {
      return max(20,
          min(244, await _ble.requestMtu(deviceId: _deviceId!, mtu: 247) - 3));
    } catch (_) {
      return 20;
    }
  }

  @override
  Future<List<int>> readInfo() =>
      _ble.readCharacteristic(_characteristic(BleProvisionProtocol.infoUuid));
  @override
  Future<List<int>> readStatus() =>
      _ble.readCharacteristic(_characteristic(BleProvisionProtocol.statusUuid));
  @override
  Future<void> write(List<int> bytes) => _ble.writeCharacteristicWithResponse(
      _characteristic(BleProvisionProtocol.commandUuid),
      value: bytes);

  @override
  Future<void> disconnect() async {
    _generation++;
    _connected = false;
    _deviceId = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await const MethodChannel('lily/platform')
            .invokeMethod<void>('cancelBondWait');
      } catch (_) {}
    }
    final scan = _scanResult;
    if (scan != null && !scan.isCompleted) {
      scan.completeError(StateError('Bluetooth scan cancelled.'));
    }
    final connection = _connectedResult;
    if (connection != null && !connection.isCompleted) {
      connection.completeError(StateError('Bluetooth connection cancelled.'));
    }
    await _scan?.cancel();
    _scan = null;
    await _connection?.cancel();
    _connection = null;
  }
}
