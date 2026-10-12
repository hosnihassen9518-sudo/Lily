import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../widgets/device_status_badge.dart';
import 'schedules_screen.dart';
import 'device_management_screen.dart';

class DeviceScreen extends StatefulWidget {
  final int deviceId;
  const DeviceScreen({super.key, required this.deviceId});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool initialized = false;
  bool lightOn = false;
  double brightness = 100;
  double volume = 50;
  Color color = Colors.white;

  Device? get device {
    for (final d in context.read<AppState>().devices) {
      if (d.id == widget.deviceId) return d;
    }
    return null;
  }

  void initialize(Device d) {
    if (initialized) return;
    lightOn = d.lightEnabled;
    brightness = d.brightness.toDouble();
    volume = d.volume.toDouble();
    color = Color.fromARGB(255, d.r, d.g, d.b);
    initialized = true;
  }

  Future<void> _run(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) await context.read<AppState>().refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
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
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
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

  Future<void> pushLight() async {
    final d = device;
    if (d == null) return;
    await _run(() => context.read<AppState>().api.setLight(
          d.id,
          enabled: lightOn,
          brightness: brightness.round(),
          r: (color.r * 255).round(),
          g: (color.g * 255).round(),
          b: (color.b * 255).round(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matches = state.devices.where((e) => e.id == widget.deviceId);
    if (matches.isEmpty) return const Scaffold(body: Center(child: Text('Device not found')));
    final d = matches.first;
    initialize(d);

    final presets = [Colors.white, Colors.orange, Colors.red, Colors.blue, Colors.green, Colors.purple];
    final room = state.rooms.where((r) => r.id == d.roomId).firstOrNull;
    final home = state.homes.where((h) => h.id == d.homeId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(d.displayName),
        actions: [
          IconButton(onPressed: () => _renameDevice(d), icon: const Icon(Icons.edit), tooltip: 'Rename device'),
          IconButton(onPressed: state.refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if(!kIsWeb) ...[
            OutlinedButton.icon(onPressed:d.status=='RESET_PENDING'?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeviceManagementScreen(device:d,wifi:true))),icon:const Icon(Icons.wifi),label:const Text('Change Wi-Fi')),
            OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeviceManagementScreen(device:d,wifi:false))),icon:const Icon(Icons.delete_outline),label:Text(d.status=='RESET_PENDING'?'Finish device reset':'Remove device')),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Info(label: 'Status', child: DeviceStatusBadge(status: d.status)),
                  _Info(label: 'Type', value: d.deviceTypeName ?? d.model),
                  _Info(label: 'Home', value: home?.name ?? 'Unassigned'),
                  _Info(label: 'Room', value: room?.name ?? 'No room'),
                  _Info(label: 'Wi-Fi', value: d.wifiRssi == null ? '—' : '${d.wifiRssi} dBm'),
                  _Info(label: 'Serial', value: d.serial),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (d.supportsLight)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(child: Text('Light', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                      Switch(
                        value: lightOn,
                        onChanged: d.online ? (v) async { setState(() => lightOn = v); await pushLight(); } : null,
                      ),
                    ]),
                    if (d.hasCapability('brightness')) ...[
                      const SizedBox(height: 12),
                      Text('Brightness: ${brightness.round()}%'),
                      Slider(
                        value: brightness,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        onChanged: d.online ? (v) => setState(() => brightness = v) : null,
                        onChangeEnd: d.online ? (_) => pushLight() : null,
                      ),
                    ],
                    if (d.hasCapability('rgb')) ...[
                      const SizedBox(height: 12),
                      const Text('Color'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        children: presets.map((preset) => InkWell(
                          onTap: d.online ? () async { setState(() => color = preset); await pushLight(); } : null,
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: preset,
                              shape: BoxShape.circle,
                              border: Border.all(color: color == preset ? Colors.black : Colors.grey.shade300, width: color == preset ? 3 : 1),
                            ),
                          ),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (d.supportsAudio) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Music', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(d.currentTrackTitle ?? (d.audioLoaded ? 'Installed audio' : 'No audio installed')),
                    const SizedBox(height: 4),
                    Text(d.audioPlaying ? 'Playing now' : 'Stopped', style: TextStyle(color: d.audioPlaying ? Colors.green : Colors.grey.shade600)),
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton.icon(
                        onPressed: d.online && d.audioLoaded ? () => _run(() => state.api.playAudio(d.id)) : null,
                        icon: const Icon(Icons.play_arrow), label: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: d.online ? () => _run(() => state.api.stopAudio(d.id)) : null,
                        icon: const Icon(Icons.stop), label: const Text('Stop'),
                      ),
                    ]),
                    if (d.hasCapability('volume')) ...[
                      const SizedBox(height: 14),
                      Text('Volume: ${volume.round()}%'),
                      Slider(
                        value: volume, min: 0, max: 100, divisions: 20,
                        onChanged: d.online ? (v) => setState(() => volume = v) : null,
                        onChangeEnd: d.online ? (v) => _run(() => state.api.setVolume(d.id, v.round())) : null,
                      ),
                    ],
                    if (!kIsWeb)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('Music installation remains available from the Music library on mobile.', style: TextStyle(color: Colors.grey.shade600)),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Placement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: d.homeId,
                    decoration: const InputDecoration(labelText: 'Home'),
                    items: state.homes.map((h) => DropdownMenuItem<int?>(value: h.id, child: Text(h.name))).toList(),
                    onChanged: (homeId) async {
                      await _run(() => state.api.moveDevice(d.id, homeId: homeId, roomId: null));
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: d.roomId,
                    decoration: const InputDecoration(labelText: 'Room'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('No room')),
                      ...state.rooms.where((r) => r.homeId == d.homeId).map((r) => DropdownMenuItem<int?>(value: r.id, child: Text(r.name))),
                    ],
                    onChanged: d.homeId == null ? null : (roomId) => _run(() => state.api.moveDevice(d.id, homeId: d.homeId, roomId: roomId)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SchedulesScreen(device: d))),
            icon: const Icon(Icons.schedule), label: const Text('Schedules'),
          ),
        ],
      ),
    );
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
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          child ?? Text(value ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
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
