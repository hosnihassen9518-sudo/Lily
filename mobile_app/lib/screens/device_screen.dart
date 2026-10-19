import '../services/light_command_queue.dart';
import '../widgets/color_wheel.dart';
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
  LightCommandQueue? _lightQueue;

  Map<String, Object?> lightValues() {
    final d = device!;
    return {
      'enabled': lightOn,
      if (d.hasCapability('brightness')) 'brightness': brightness.round(),
      if (d.hasCapability('rgb')) ...{
        'r': (color.r * 255).round(),
        'g': (color.g * 255).round(),
        'b': (color.b * 255).round(),
      },
    };
  }

  void queueLight() {
    _lightQueue?.enqueue(lightValues());
  }

  Future<void> flushLight() async {
    await _lightQueue?.enqueue(lightValues(), immediate: true);
  }

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
    final api = context.read<AppState>().api;
    _lightQueue = api.lightCommandsFor(d.id, onError: (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    });
    _lightQueue?.reconcile();
    final pending = _lightQueue?.latestIntent;
    if (pending != null) {
      lightOn = pending['enabled'] as bool;
      brightness = (pending['brightness'] as int? ?? d.brightness).toDouble();
      color = Color.fromARGB(255, pending['r'] as int? ?? d.r,
          pending['g'] as int? ?? d.g, pending['b'] as int? ?? d.b);
    }
    initialized = true;
  }

  Future<void> _run(Future<void> Function() fn, {bool refresh = true}) async {
    try {
      await fn();
      if (mounted && refresh) await context.read<AppState>().refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
                                await flushLight();
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
                        divisions: 100,
                        onChanged: d.online
                            ? (v) {
                                setState(() => brightness = v);
                                queueLight();
                              }
                            : null,
                        onChangeEnd: d.online ? (_) => flushLight() : null,
                      ),
                    ],
                    if (d.hasCapability('rgb')) ...[
                      const SizedBox(height: 12),
                      const Text('Color'),
                      const SizedBox(height: 10),
                      ColorWheel(
                        color: color,
                        onChanged: d.online
                            ? (value) {
                                setState(() => color = value);
                                queueLight();
                              }
                            : null,
                        onChangeEnd: d.online ? flushLight : null,
                      ),
                      Center(
                          child: TextButton(
                        onPressed: d.online
                            ? () {
                                setState(() => color = Colors.white);
                                flushLight();
                              }
                            : null,
                        child: const Text('White'),
                      )),
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
