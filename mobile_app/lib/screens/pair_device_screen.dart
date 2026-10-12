import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_provision_service.dart';
import '../services/ble_provision_protocol.dart';
import '../state/app_state.dart';

class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key, this.provisionService});
  final BleProvisionService? provisionService;
  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  BleProvisionService? provision;
  final wifiName = TextEditingController();
  final wifiPassword = TextEditingController();
  final deviceName = TextEditingController();
  List<Map<String, dynamic>> homeNetworks = [];
  bool manualWifi = false;
  bool busy = false;
  bool registered = false;
  int step = 0;
  String message = '';
  List<BleSetupDevice> devices = [];
  String? selectedDeviceId;
  Map<String, dynamic>? deviceInfo;
  int? selectedHomeId;
  int? selectedRoomId;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (supported || widget.provisionService != null) {
      provision = widget.provisionService ?? BleProvisionService();
      unawaited(scanLily());
    }
  }

  @override
  void dispose() {
    final service = provision;
    if (service != null) unawaited(service.dispose().catchError((Object _) {}));
    wifiName.dispose();
    wifiPassword.dispose();
    deviceName.dispose();
    super.dispose();
  }

  String errorText(Object error) => error.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state|FormatException|TimeoutException):\s*'),
      '');

  Future<void> scanLily() async {
    if (busy || provision == null) return;
    setState(() {
      busy = true;
      message = 'Scanning for Lily Bluetooth devices...';
    });
    try {
      final result = await provision!.scanDevices();
      if (!mounted) return;
      setState(() {
        devices = result;
        selectedDeviceId = result.isEmpty ? null : result.first.id;
        message = result.isEmpty
            ? 'No Lily device found. Power on Lily with updated firmware and enable Bluetooth.'
            : 'Choose your Lily device.';
      });
    } catch (error) {
      if (mounted) setState(() => message = errorText(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connectDevice() async {
    if (busy || selectedDeviceId == null) return;
    final selected = devices.firstWhere((d) => d.id == selectedDeviceId);
    setState(() {
      busy = true;
      message =
          'Connecting over Bluetooth. Enter the pairing PIN from the ESP32 Serial Monitor when prompted.';
    });
    try {
      final info = await provision!.connect(selected);
      if (!mounted) return;
      final state = context.read<AppState>();
      if(info['reset_pending']==true) {
        final status=await provision!.runManagementCommand('receipt',{});
        final receipt=(status['receipt'] as Map?)?.cast<String,dynamic>();
        if(receipt==null || receipt['signature']==null)throw StateError('Lily is still erasing settings. Reconnect and retry.');
        await state.api.submitResetReceipt(receipt);
        final current=await provision!.readManagementInfo();
        final operationId=(receipt['body'] as String).split('|')[2];
        final authorization=await state.api.createResetAuthorization(operationId,current['challenge'] as String,completion:true);
        await provision!.runManagementCommand('reset_ack',{'challenge':current['challenge'],'authorization':authorization['authorization']});
        await provision!.disconnect();
        throw StateError('Reset confirmed. Lily is restarting Bluetooth setup. Scan and connect again.');
      }
      setState(() {
        deviceInfo = info;
        deviceName.text =
            info['device_type_name']?.toString() ?? 'Lily';
        selectedHomeId = state.homes.isEmpty ? null : state.homes.first.id;
        selectedRoomId = null;
        registered = false;
        step = 1;
        message =
            'Bluetooth connected and paired. Scanning Wi-Fi networks visible to the ESP32...';
      });
      await loadHomeNetworks();
    } catch (error) {
      if (mounted) setState(() => message = errorText(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadHomeNetworks() async {
    try {
      final networks = await provision!.scanHomeNetworks();
      if (!mounted) return;
      setState(() {
        homeNetworks = networks;
        if (!networks.any((n) => n['ssid'] == wifiName.text)) {
          wifiName.text =
              networks.isEmpty ? '' : networks.first['ssid'] as String;
        }
        manualWifi = networks.isEmpty;
        message = networks.isEmpty
            ? 'The ESP32 found no Wi-Fi networks. Scan again or enter a hidden network manually.'
            : 'Select a Wi-Fi network seen by the ESP32. Your phone stays on its normal network.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          manualWifi = true;
          message = 'Could not load ESP32 Wi-Fi networks. ${errorText(error)}';
        });
      }
    }
  }

  Future<void> rescanHomeNetworks() async {
    if (busy || registered) return;
    setState(() {
      busy = true;
      message = 'The ESP32 is scanning nearby Wi-Fi...';
    });
    try {
      await loadHomeNetworks();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> provisionHomeWifi() async {
    if (busy) return;
    final name = deviceName.text.trim();
    final ssid = wifiName.text;
    final password = wifiPassword.text;
    final homeId = selectedHomeId;
    final roomId = selectedRoomId;
    if (name.isEmpty) {
      setState(() => message = 'Give the device a name before continuing.');
      return;
    }
    if (!registered) {
      try {
        BleProvisionProtocol.validateCredentials(ssid, password);
      } catch (error) {
        setState(() => message = errorText(error));
        return;
      }
    }
    final state = context.read<AppState>();
    setState(() {
      busy = true;
      message = registered
          ? 'Finishing device name and placement...'
          : 'Creating setup session...';
    });
    try {
      if (!registered) {
        await provision!.provision(
            ssid: ssid,
            password: password,
            createToken: state.api.createPairingToken,
            onProgress: (stage) {
              if (!mounted) return;
              setState(() => message = switch (stage) {
                    'connecting_wifi' => 'Lily is connecting to home Wi-Fi...',
                    'activating' =>
                      'Wi-Fi connected. Registering Lily with the backend...',
                    'success' =>
                      'Lily registered. Finishing device name and placement...',
                    _ => 'Sending Wi-Fi settings securely over Bluetooth...',
                  });
            });
        registered = true;
        if (!mounted) return;
        wifiPassword.clear();
        await provision!.disconnect();
      }
      await state.refresh();
      final matched = state.devices
          .where((d) => d.serial == deviceInfo?['serial'])
          .toList();
      if (matched.isEmpty) {
        throw StateError(
            'The registered device is not yet listed by the backend.');
      }
      await state.api.renameDevice(matched.first.id, name);
      if (homeId != null) {
        await state.api
            .moveDevice(matched.first.id, homeId: homeId, roomId: roomId);
      }
      await state.refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => message = registered
          ? 'Lily is registered, but name or placement could not be saved. Tap Retry finishing setup. ${errorText(error)}'
          : errorText(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reconnect() async {
    await provision!.disconnect();
    if (!mounted) return;
    setState(() {
      step = 0;
      deviceInfo = null;
    });
    await scanLily();
  }

  @override
  Widget build(BuildContext context) {
    if (!supported && widget.provisionService == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Add device')),
          body: const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Bluetooth setup is available in the Android and iOS mobile app.'))));
    }
    final state = context.watch<AppState>();
    final rooms = state.rooms.where((r) => r.homeId == selectedHomeId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add a Lily device')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (message.isNotEmpty)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(message))),
                if (busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                if (step == 0) ...[
                  const Text('1. Connect over Bluetooth',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                      'Keep your phone on normal Wi-Fi. Lily uses Bluetooth only for setup. The pairing PIN is printed in the ESP32 Serial Monitor.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedDeviceId),
                    initialValue: selectedDeviceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Available Lily devices'),
                    items: devices
                        .map((d) =>
                            DropdownMenuItem(value: d.id, child: Text(d.name)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => selectedDeviceId = value),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    OutlinedButton.icon(
                        onPressed: busy ? null : scanLily,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Scan again')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: FilledButton.icon(
                            onPressed: busy || selectedDeviceId == null
                                ? null
                                : connectDevice,
                            icon: const Icon(Icons.bluetooth),
                            label: const Text('Connect'))),
                  ]),
                ],
                if (step == 1) ...[
                  const Text('2. Configure home Wi-Fi',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  ListTile(
                      leading: const Icon(Icons.memory),
                      title: Text(deviceInfo?['device_type_name']?.toString() ??
                          'Lily'),
                      subtitle: Text(deviceInfo?['serial']?.toString() ?? '')),
                  TextField(
                      controller: deviceName,
                      enabled: !busy,
                      maxLength: 120,
                      decoration: const InputDecoration(
                          labelText: 'Device name',
                          helperText: 'Example: Living Room Light')),
                  const SizedBox(height: 12),
                  if (!manualWifi)
                    DropdownButtonFormField<String>(
                      key: ValueKey('wifi-${wifiName.text}'),
                      initialValue:
                          wifiName.text.isEmpty ? null : wifiName.text,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Wi-Fi networks seen by ESP32'),
                      items: homeNetworks
                          .map((n) => DropdownMenuItem(
                              value: n['ssid'] as String,
                              child: Text(
                                  '${n['ssid']} (${n['rssi']} dBm)${n['secure'] == true ? ' 🔒' : ''}')))
                          .toList(),
                      onChanged: busy || registered
                          ? null
                          : (ssid) =>
                              setState(() => wifiName.text = ssid ?? ''),
                    ),
                  if (manualWifi)
                    TextField(
                        controller: wifiName,
                        enabled: !busy && !registered,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Home Wi-Fi name (SSID)',
                            helperText:
                                'Enter the exact name of a 2.4 GHz network.')),
                  if (!registered)
                    Row(children: [
                      TextButton.icon(
                          onPressed: busy ? null : rescanHomeNetworks,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Scan Wi-Fi again')),
                      Expanded(
                          child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                        manualWifi = !manualWifi;
                                        if (!manualWifi &&
                                            !homeNetworks.any((n) =>
                                                n['ssid'] == wifiName.text)) {
                                          wifiName.text = homeNetworks.isEmpty
                                              ? ''
                                              : homeNetworks.first['ssid']
                                                  as String;
                                        }
                                      }),
                              child: Text(manualWifi
                                  ? 'Choose from list'
                                  : 'Enter manually'))),
                    ]),
                  const SizedBox(height: 12),
                  TextField(
                      controller: wifiPassword,
                      enabled: !busy && !registered,
                      obscureText: true,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'Wi-Fi password',
                          helperText: 'Leave empty only for an open network.')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('home-$selectedHomeId'),
                    initialValue: selectedHomeId,
                    decoration:
                        const InputDecoration(labelText: 'Home (optional)'),
                    items: state.homes
                        .map((h) =>
                            DropdownMenuItem(value: h.id, child: Text(h.name)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (id) => setState(() {
                              selectedHomeId = id;
                              selectedRoomId = null;
                            }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('room-$selectedHomeId-$selectedRoomId'),
                    initialValue: selectedRoomId,
                    decoration:
                        const InputDecoration(labelText: 'Room (optional)'),
                    items: [
                      const DropdownMenuItem<int>(
                          value: null, child: Text('No room')),
                      ...rooms.map((r) =>
                          DropdownMenuItem(value: r.id, child: Text(r.name)))
                    ],
                    onChanged: busy
                        ? null
                        : (id) => setState(() => selectedRoomId = id),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: busy ? null : provisionHomeWifi,
                      icon: const Icon(Icons.wifi),
                      label: Text(registered
                          ? 'Retry finishing setup'
                          : 'Connect and add device')),
                  if (!registered)
                    TextButton(
                        onPressed: busy ? null : reconnect,
                        child: const Text('Reconnect Bluetooth')),
                ],
                if (step == 2) ...[
                  const Icon(Icons.check_circle, size: 70),
                  const SizedBox(height: 16),
                  const Text('Your Lily device is ready.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done')),
                ],
              ]))),
    );
  }
}
