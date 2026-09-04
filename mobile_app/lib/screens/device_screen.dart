import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../widgets/device_status_badge.dart';
import 'schedules_screen.dart';

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
    final list = context.read<AppState>().devices;
    for (final d in list) {
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

  Future<void> pushLight() async {
    final d = device;
    if (d == null) return;
    await context.read<AppState>().api.setLight(
          d.id,
          enabled: lightOn,
          brightness: brightness.round(),
          r: (color.r * 255).round(),
          g: (color.g * 255).round(),
          b: (color.b * 255).round(),
        );
    await context.read<AppState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final d = state.devices.where((e) => e.id == widget.deviceId).firstOrNull;

    if (d == null) {
      return const Scaffold(body: Center(child: Text('Device not found')));
    }

    initialize(d);

    final presets = [
      Colors.white,
      Colors.orange,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(d.displayName),
        actions: [
          IconButton(
            onPressed: state.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.serial),
                        const SizedBox(height: 8),
                        DeviceStatusBadge(status: d.status),
                      ],
                    ),
                  ),
                  Text(
                    d.wifiRssi == null ? 'Wi-Fi —' : '${d.wifiRssi} dBm',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Light',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Switch(
                        value: lightOn,
                        onChanged: d.online
                            ? (value) async {
                                setState(() => lightOn = value);
                                await pushLight();
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Brightness'),
                  Slider(
                    value: brightness,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${brightness.round()}%',
                    onChanged: d.online
                        ? (value) => setState(() => brightness = value)
                        : null,
                    onChangeEnd: d.online ? (_) => pushLight() : null,
                  ),
                  const SizedBox(height: 12),
                  const Text('Color'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: presets
                        .map(
                          (preset) => InkWell(
                            onTap: d.online
                                ? () async {
                                    setState(() => color = preset);
                                    await pushLight();
                                  }
                                : null,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: preset,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == preset
                                      ? Colors.black
                                      : Colors.grey.shade300,
                                  width: color == preset ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Audio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(d.audioLoaded ? 'Audio installed' : 'No audio installed'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: d.online && d.audioLoaded
                            ? () async {
                                await state.api.playAudio(d.id);
                                await state.refresh();
                              }
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: d.online
                            ? () async {
                                await state.api.stopAudio(d.id);
                                await state.refresh();
                              }
                            : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Volume'),
                  Slider(
                    value: volume,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${volume.round()}%',
                    onChanged: d.online
                        ? (value) => setState(() => volume = value)
                        : null,
                    onChangeEnd: d.online
                        ? (value) async {
                            await state.api.setVolume(d.id, value.round());
                            await state.refresh();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SchedulesScreen(device: d),
              ),
            ),
            icon: const Icon(Icons.schedule),
            label: const Text('Schedules'),
          ),
        ],
      ),
    );
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
