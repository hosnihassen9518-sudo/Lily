import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../services/ble_provision_service.dart';
import '../services/ble_provision_protocol.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen(
      {super.key, required this.device, required this.wifi});
  final Device device;
  final bool wifi;
  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  final ble = BleProvisionService();
  final ssid = TextEditingController();
  final password = TextEditingController();
  List<BleSetupDevice> nearby = [];
  List<Map<String, dynamic>> networks = [];
  Map<String, dynamic>? operation;
  bool busy = false, connected = false, finished = false;
  String message = '';
  @override
  void initState() {
    super.initState();
    if (widget.device.status == 'RESET_PENDING') {
      WidgetsBinding.instance.addPostFrameCallback((_) => run(startRemoval));
    }
  }

  @override
  void dispose() {
    ble.dispose();
    ssid.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startRemoval() async {
    final api = context.read<AppState>().api;
    final result = await api.removeDevice(widget.device.id);
    if (!mounted) return;
    setState(() => operation = result);
    await checkProgress();
  }

  Future<void> checkProgress() async {
    if (operation == null) return;
    final result = await context
        .read<AppState>()
        .api
        .getDeviceOperation(operation!['operation_id'] as String);
    if (!mounted) return;
    setState(() {
      operation = result;
      finished = result['status'] == 'completed';
      message = finished
          ? 'Device settings erased and account removal confirmed.'
          : 'Reset pending. If Lily is offline, connect nearby through Bluetooth to finish.';
    });
    await context.read<AppState>().refresh();
  }

  Future<void> confirmRemoval() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Remove and reset device?'),
                content: const Text(
                    'This erases saved Wi-Fi, schedules, downloaded audio, and other user settings. Lily will return to Bluetooth setup. An offline device stays reset pending until it can be reset.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove and reset'))
                ]));
    if (yes == true && mounted) await run(startRemoval);
  }

  Future<void> scan() async {
    final results = await ble.scanDevices();
    if (!mounted) return;
    setState(() {
      nearby = results;
      connected = false;
      message = results.isEmpty
          ? 'No Lily devices found. Move closer and scan again.'
          : '';
    });
  }

  Future<void> connect(BleSetupDevice item) async {
    final info = await ble.connect(item);
    if (info['serial'] != widget.device.serial || info['management'] != true) {
      await ble.disconnect();
      throw StateError(
          'Select this Lily device and install compatible 0.8.0 firmware.');
    }
    if (!mounted) return;
    setState(() => connected = true);
    if (widget.wifi) {
      final results = await ble.scanHomeNetworks();
      if (mounted) setState(() => networks = results);
    }
  }

  Future<void> updateWifi() async {
    BleProvisionProtocol.validateCredentials(ssid.text, password.text);
    final api = context.read<AppState>().api;
    final info = await ble.readManagementInfo();
    if (info['serial'] != widget.device.serial) {
      throw StateError('Device identity changed. Reconnect.');
    }
    final authorization = await api.createWifiSession(
        widget.device.id, info['challenge'] as String);
    await ble.runManagementCommand('update_wifi', {
      'ssid': ssid.text,
      'password': password.text,
      'challenge': info['challenge'],
      'authorization': authorization['authorization']
    });
    password.clear();
    if (mounted) setState(() => message = 'Wi-Fi updated.');
  }

  Future<void> localReset() async {
    if (operation == null) throw StateError('Request removal first.');
    final api = context.read<AppState>().api;
    var info = await ble.readManagementInfo();
    if (info['serial'] != widget.device.serial) {
      throw StateError('Device identity changed.');
    }
    if (info['reset_pending'] != true && operation?['status'] == 'completed') {
      await checkProgress();
      return;
    }
    if (info['reset_pending'] != true) {
      final auth = await api.createResetAuthorization(
          operation!['operation_id'] as String, info['challenge'] as String);
      await ble.runManagementCommand('reset', {
        'challenge': info['challenge'],
        'authorization': auth['authorization']
      });
    }
    final status = await ble.runManagementCommand('receipt', {});
    final receipt = (status['receipt'] as Map?)?.cast<String, dynamic>();
    if (receipt == null || receipt['signature'] == null) {
      throw StateError('Reset is not yet complete. Reconnect and retry.');
    }
    await api.submitResetReceipt(receipt);
    info = await ble.readManagementInfo();
    final auth = await api.createResetAuthorization(
        operation!['operation_id'] as String, info['challenge'] as String,
        completion: true);
    await ble.runManagementCommand('reset_ack', {
      'challenge': info['challenge'],
      'authorization': auth['authorization']
    });
    await checkProgress();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: Text(widget.wifi ? 'Change Wi-Fi' : 'Remove device')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(widget.device.displayName,
            style: Theme.of(context).textTheme.titleLarge),
        Text(widget.device.serial),
        const SizedBox(height: 16),
        if (!widget.wifi && operation == null)
          FilledButton(
              onPressed: busy ? null : confirmRemoval,
              child: const Text('Remove and reset')),
        if (!widget.wifi && operation != null)
          OutlinedButton(
              onPressed: busy ? null : () => run(checkProgress),
              child: const Text('Check reset progress')),
        if (message.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(message)),
        if (!finished || !widget.wifi) ...[
          const Text(
              'Keep the phone near Lily with Bluetooth enabled. Confirm the Android pairing request if it appears.'),
          OutlinedButton(
              onPressed: busy ? null : () => run(scan),
              child: const Text('Find Lily over Bluetooth')),
          ...nearby.map((item) => ListTile(
              title: Text(item.name),
              trailing: const Icon(Icons.bluetooth),
              onTap: busy ? null : () => run(() => connect(item)))),
          if (connected && widget.wifi) ...[
            DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Nearby Wi-Fi'),
                items: networks
                    .map((n) => DropdownMenuItem(
                        value: n['ssid'] as String,
                        child: Text(n['ssid'] as String)))
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) ssid.text = value;
                      }),
            TextField(
                controller: ssid,
                decoration: const InputDecoration(
                    labelText: 'Wi-Fi name (or enter a hidden network)')),
            TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Wi-Fi password')),
            FilledButton(
                onPressed: busy ? null : () => run(updateWifi),
                child: const Text('Save Wi-Fi')),
          ],
          if (connected && !widget.wifi && operation != null)
            FilledButton(
                onPressed: busy ? null : () => run(localReset),
                child: const Text('Finish reset over Bluetooth')),
        ],
        if (busy) const Center(child: CircularProgressIndicator()),
      ]));
}
