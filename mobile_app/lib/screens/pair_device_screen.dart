import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/provision_service.dart';
import '../state/app_state.dart';

class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final provision = ProvisionService();
  final wifiPassword = TextEditingController();

  bool busy = false;
  int step = 0;
  String message = '';
  List<String> lilyNetworks = [];
  String? selectedLilyNetwork;
  Map<String, dynamic>? deviceInfo;
  List<Map<String, dynamic>> homeNetworks = [];
  String? selectedHomeWifi;
  int? selectedHomeId;
  int? selectedRoomId;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) scanLily();
  }

  Future<void> scanLily() async {
    setState(() {
      busy = true;
      message = 'Scanning for Lily devices...';
    });
    try {
      final result = await provision.scanLilyNetworks();
      setState(() {
        lilyNetworks = result;
        selectedLilyNetwork = result.isNotEmpty ? result.first : null;
        message = result.isEmpty
            ? 'No Lily setup network found. Make sure the device is powered on and in setup mode.'
            : '${result.length} Lily device${result.length == 1 ? '' : 's'} found.';
      });
    } catch (e) {
      setState(() => message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> connectDevice() async {
    final ssid = selectedLilyNetwork;
    if (ssid == null) return;
    setState(() {
      busy = true;
      message = 'Connecting to $ssid...';
    });
    try {
      final connected = await provision.connectToDeviceAp(ssid);
      if (!connected) throw Exception('Could not join the Lily setup network.');
      final info = await provision.getDeviceInfo();
      final serial = info['serial']?.toString() ?? '';
      final type = info['device_type_name']?.toString() ?? info['model']?.toString() ?? 'Lily device';
      if (serial.isEmpty) throw Exception('The setup network did not return a valid Lily serial number.');

      final networks = await provision.getNearbyHomeNetworks();
      final state = context.read<AppState>();
      setState(() {
        deviceInfo = info;
        homeNetworks = networks;
        selectedHomeWifi = networks.isNotEmpty ? networks.first['ssid']?.toString() : null;
        selectedHomeId = state.homes.isNotEmpty ? state.homes.first.id : null;
        selectedRoomId = null;
        step = 1;
        message = 'Connected to $type ($serial). Select the home Wi-Fi for this device.';
      });
    } catch (e) {
      setState(() => message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> provisionHomeWifi() async {
    final ssid = selectedHomeWifi;
    if (ssid == null || ssid.isEmpty) {
      setState(() => message = 'Select a Wi-Fi network first.');
      return;
    }
    setState(() {
      busy = true;
      message = 'Testing Wi-Fi credentials and registering the device...';
    });

    try {
      final state = context.read<AppState>();
      final pairingToken = await state.api.createPairingToken();
      await provision.provisionWifi(
        wifiSsid: ssid,
        wifiPassword: wifiPassword.text,
        pairingToken: pairingToken,
      );

      await provision.disconnectFromDeviceAp();
      await Future.delayed(const Duration(seconds: 2));
      await state.refresh();

      final serial = deviceInfo?['serial']?.toString();
      final matched = state.devices.where((d) => d.serial == serial).toList();
      if (matched.isNotEmpty && selectedHomeId != null) {
        await state.api.moveDevice(
          matched.first.id,
          homeId: selectedHomeId,
          roomId: selectedRoomId,
        );
        await state.refresh();
      }

      setState(() {
        step = 2;
        message = 'Device connected, registered, and added successfully.';
      });
    } catch (e) {
      setState(() {
        message = e.toString().replaceFirst('Exception: ', '');
        step = 1;
      });
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add device')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Adding Lily devices is available only in the mobile app.'),
          ),
        ),
      );
    }

    final state = context.watch<AppState>();
    final rooms = selectedHomeId == null
        ? const []
        : state.rooms.where((r) => r.homeId == selectedHomeId).toList();
    final capabilities = (deviceInfo?['capabilities'] as List<dynamic>? ?? const []).map((e) => e.toString()).join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Add a Lily device')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (message.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(step == 2 ? Icons.check_circle : Icons.info_outline),
                        const SizedBox(width: 10),
                        Expanded(child: Text(message)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (step == 0) ...[
                const Text('1. Choose your Lily device', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Only open Wi-Fi networks whose name starts with LILY- are shown.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedLilyNetwork,
                  items: lilyNetworks.map((ssid) => DropdownMenuItem(value: ssid, child: Text(ssid))).toList(),
                  onChanged: busy ? null : (value) => setState(() => selectedLilyNetwork = value),
                  decoration: const InputDecoration(labelText: 'Available Lily devices'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(onPressed: busy ? null : scanLily, icon: const Icon(Icons.refresh), label: const Text('Scan again')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy || selectedLilyNetwork == null ? null : connectDevice,
                        child: Text(busy ? 'Please wait...' : 'Connect'),
                      ),
                    ),
                  ],
                ),
              ],
              if (step == 1) ...[
                const Text('2. Configure home Wi-Fi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (deviceInfo != null)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.memory)),
                      title: Text(deviceInfo!['device_type_name']?.toString() ?? 'Lily device'),
                      subtitle: Text('${deviceInfo!['serial']}\nCapabilities: $capabilities'),
                      isThreeLine: true,
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedHomeWifi,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Available home Wi-Fi'),
                  items: homeNetworks.map((network) {
                    final ssid = network['ssid']?.toString() ?? '';
                    final rssi = network['rssi']?.toString() ?? '—';
                    final secure = network['secure'] == true;
                    return DropdownMenuItem(value: ssid, child: Text('$ssid  ($rssi dBm)${secure ? ' 🔒' : ''}'));
                  }).toList(),
                  onChanged: busy ? null : (value) => setState(() => selectedHomeWifi = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: wifiPassword,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Wi-Fi password', helperText: 'Leave empty only for an open home network.'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedHomeId,
                  decoration: const InputDecoration(labelText: 'Home'),
                  items: state.homes.map((home) => DropdownMenuItem(value: home.id, child: Text(home.name))).toList(),
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                            selectedHomeId = value;
                            selectedRoomId = null;
                          }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: selectedRoomId,
                  decoration: const InputDecoration(labelText: 'Room (optional)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No room')),
                    ...rooms.map((room) => DropdownMenuItem<int?>(value: room.id, child: Text(room.name))),
                  ],
                  onChanged: busy ? null : (value) => setState(() => selectedRoomId = value),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : provisionHomeWifi,
                  icon: const Icon(Icons.wifi),
                  label: Text(busy ? 'Testing connection...' : 'Connect and add device'),
                ),
              ],
              if (step == 2) ...[
                const Icon(Icons.check_circle, size: 70),
                const SizedBox(height: 16),
                const Text('Your Lily device is ready.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
