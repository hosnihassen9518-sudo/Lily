import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../widgets/device_status_badge.dart';
import 'device_management_screen.dart';

class DeviceConfigurationScreen extends StatefulWidget {
  final int deviceId;
  const DeviceConfigurationScreen({super.key, required this.deviceId});
  @override
  State<DeviceConfigurationScreen> createState() =>
      _DeviceConfigurationScreenState();
}

class _DeviceConfigurationScreenState extends State<DeviceConfigurationScreen> {
  Future<void> _run(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) await context.read<AppState>().refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _renameDevice(Device d) async {
    final controller = TextEditingController(text: d.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name == d.displayName) return;
    await _run(() => context.read<AppState>().api.renameDevice(d.id, name));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final d = state.devices.where((d) => d.id == widget.deviceId).firstOrNull;
    if (d == null) {
      return const Scaffold(body: Center(child: Text('Device not found')));
    }
    final room = state.rooms.where((r) => r.id == d.roomId).firstOrNull;
    final home = state.homes.where((h) => h.id == d.homeId).firstOrNull;
    return Scaffold(
        appBar: AppBar(title: const Text('Configuration')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          ListTile(
              title: Text(d.displayName),
              subtitle: const Text('Rename device'),
              trailing: const Icon(Icons.edit),
              onTap: () => _renameDevice(d)),
          const Text('Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Info(
                      label: 'Status',
                      child: DeviceStatusBadge(status: d.status)),
                  _Info(label: 'Type', value: d.deviceTypeName ?? d.model),
                  _Info(label: 'Home', value: home?.name ?? 'Unassigned'),
                  _Info(label: 'Room', value: room?.name ?? 'No room'),
                  _Info(
                      label: 'Wi-Fi',
                      value: d.wifiRssi == null ? '—' : '${d.wifiRssi} dBm'),
                  _Info(label: 'Serial', value: d.serial),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Location',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    key: ValueKey('home-${d.homeId}'),
                    initialValue: d.homeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Home'),
                    items: state.homes
                        .map((h) => DropdownMenuItem<int?>(
                            value: h.id, child: Text(h.name)))
                        .toList(),
                    onChanged: (homeId) async {
                      await _run(() => state.api
                          .moveDevice(d.id, homeId: homeId, roomId: null));
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    key: ValueKey('room-${d.homeId}-${d.roomId}'),
                    initialValue: d.roomId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Room'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('No room')),
                      ...state.rooms.where((r) => r.homeId == d.homeId).map(
                          (r) => DropdownMenuItem<int?>(
                              value: r.id, child: Text(r.name))),
                    ],
                    onChanged: d.homeId == null
                        ? null
                        : (roomId) => _run(() => state.api.moveDevice(d.id,
                            homeId: d.homeId, roomId: roomId)),
                  ),
                ],
              ),
            ),
          ),
          if (!kIsWeb) ...[
            OutlinedButton.icon(
                onPressed: d.status == 'RESET_PENDING'
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                DeviceManagementScreen(device: d, wifi: true))),
                icon: const Icon(Icons.wifi),
                label: const Text('Change Wi-Fi')),
            const SizedBox(height: 24),
            OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            DeviceManagementScreen(device: d, wifi: false))),
                icon: const Icon(Icons.delete_outline),
                label: Text(d.status == 'RESET_PENDING'
                    ? 'Finish device reset'
                    : 'Remove device')),
          ],
        ]));
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  const _Info({required this.label, this.value, this.child});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          child ??
              Text(value ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
