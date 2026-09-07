import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../screens/device_screen.dart';
import 'device_status_badge.dart';

class DeviceCard extends StatelessWidget {
  final Device device;
  const DeviceCard({super.key, required this.device});

  Future<void> _turnOff(BuildContext context) async {
    if (!device.online) return;
    try {
      if (device.supportsLight) {
        await context.read<AppState>().api.setLight(
              device.id,
              enabled: false,
              brightness: device.brightness,
              r: device.r,
              g: device.g,
              b: device.b,
            );
      } else {
        await context.read<AppState>().api.genericCommand(
          device.id,
          'power',
          {'enabled': false},
        );
      }
      await context.read<AppState>().refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _play(BuildContext context) async {
    if (!device.online || !device.supportsAudio || !device.audioLoaded) return;
    try {
      if (device.audioPlaying) {
        await context.read<AppState>().api.stopAudio(device.id);
      } else {
        await context.read<AppState>().api.playAudio(device.id);
      }
      await context.read<AppState>().refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _open(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: device.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: device.online
                        ? Colors.green.withValues(alpha: .12)
                        : Colors.grey.withValues(alpha: .12),
                    child: Icon(
                      device.supportsAudio ? Icons.speaker : Icons.lightbulb,
                      color: device.online ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(device.deviceTypeName ?? device.model,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                  DeviceStatusBadge(status: device.status),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: device.online ? () => _turnOff(context) : null,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Off'),
                  ),
                  OutlinedButton.icon(
                    onPressed: device.online && device.supportsAudio && device.audioLoaded
                        ? () => _play(context)
                        : null,
                    icon: Icon(device.audioPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(device.audioPlaying ? 'Stop' : 'Play'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.tune),
                    label: const Text('More'),
                  ),
                ],
              ),
              if (device.audioPlaying) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.graphic_eq, size: 18),
                    SizedBox(width: 6),
                    Text('Music playing', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
