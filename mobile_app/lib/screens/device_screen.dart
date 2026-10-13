import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';

import 'schedules_screen.dart';
import 'device_configuration_screen.dart';

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

  Future<void> pushLight() async {
    final d = device;
    if (d == null) return;
    await _run(() => context.read<AppState>().api.setLight(
          d.id,
          enabled: lightOn,
          brightness: d.hasCapability('brightness') ? brightness.round() : null,
          r: d.hasCapability('rgb') ? (color.r * 255).round() : null,
          g: d.hasCapability('rgb') ? (color.g * 255).round() : null,
          b: d.hasCapability('rgb') ? (color.b * 255).round() : null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matches = state.devices.where((e) => e.id == widget.deviceId);
    if (matches.isEmpty) {
      return const Scaffold(body: Center(child: Text('Device not found')));
    }
    final d = matches.first;
    initialize(d);

    final presets = [
      Colors.white,
      Colors.orange,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Expanded(child: Text(d.displayName)),
          const SizedBox(width: 12),
          Semantics(
              label: d.online ? 'Device online' : 'Device offline',
              child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d.online ? Colors.green : Colors.red)))
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (d.hasCapability('power') && !d.supportsLight)
            Card(
                child: SwitchListTile(
                    title: const Text('Power'),
                    value: d.genericState['enabled'] == true,
                    onChanged: d.online
                        ? (v) => _run(() => state.api
                            .genericCommand(d.id, 'power', {'enabled': v}))
                        : null)),
          if (d.supportsLight)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Light',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800))),
                      Switch(
                        value: lightOn,
                        onChanged: d.online
                            ? (v) async {
                                setState(() => lightOn = v);
                                await pushLight();
                              }
                            : null,
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
                        onChanged: d.online
                            ? (v) => setState(() => brightness = v)
                            : null,
                        onChangeEnd: d.online ? (_) => pushLight() : null,
                      ),
                    ],
                    if (d.hasCapability('rgb')) ...[
                      const SizedBox(height: 12),
                      const Text('Color'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        children: presets
                            .map((preset) => InkWell(
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
                                          width: color == preset ? 3 : 1),
                                    ),
                                  ),
                                ))
                            .toList(),
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
                    const Text('Music',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(d.currentTrackTitle ??
                        (d.audioLoaded
                            ? 'Installed audio'
                            : 'No audio installed')),
                    const SizedBox(height: 4),
                    Text(d.audioPlaying ? 'Playing now' : 'Stopped',
                        style: TextStyle(
                            color: d.audioPlaying
                                ? Colors.green
                                : Colors.grey.shade600)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: d.online && d.audioLoaded
                            ? () => _run(() => state.api.playAudio(d.id))
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                      OutlinedButton.icon(
                        onPressed: d.online
                            ? () => _run(() => state.api.stopAudio(d.id))
                            : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ]),
                    if (d.hasCapability('volume')) ...[
                      const SizedBox(height: 14),
                      Text('Volume: ${volume.round()}%'),
                      Slider(
                        value: volume,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        onChanged:
                            d.online ? (v) => setState(() => volume = v) : null,
                        onChangeEnd: d.online
                            ? (v) =>
                                _run(() => state.api.setVolume(d.id, v.round()))
                            : null,
                      ),
                    ],
                    if (!kIsWeb)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                            'Music installation remains available from the Music library on mobile.',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (d.supportsLight || d.supportsAudio)
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SchedulesScreen(device: d))),
              icon: const Icon(Icons.schedule),
              label: const Text('Schedules'),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          DeviceConfigurationScreen(deviceId: d.id))),
              icon: const Icon(Icons.settings),
              label: const Text('Configuration')),
        ],
      ),
    );
  }
}
