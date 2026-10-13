import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../screens/device_screen.dart';
import 'device_status_badge.dart';

class DeviceCard extends StatefulWidget {
  final Device device;
  const DeviceCard({super.key, required this.device});

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  Device get device => widget.device;
  bool sendingPower = false;

  Future<void> _switchPower(BuildContext context) async {
    if (!device.online || sendingPower) return;
    final state = context.read<AppState>();
    setState(() => sendingPower = true);
    try {
      if (device.supportsLight) {
        await state.api.setLight(
          device.id,
          enabled: !device.lightEnabled,
          brightness:
              device.hasCapability('brightness') ? device.brightness : null,
          r: device.hasCapability('rgb') ? device.r : null,
          g: device.hasCapability('rgb') ? device.g : null,
          b: device.hasCapability('rgb') ? device.b : null,
        );
      } else {
        await state.api.genericCommand(
          device.id,
          'power',
          {'enabled': device.genericState['enabled'] != true},
        );
      }
      await state.refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => sendingPower = false);
    }
  }

  Future<void> _play(BuildContext context) async {
    if (!device.online || !device.supportsAudio || !device.audioLoaded) return;
    try {
      if (device.supportsAudio && device.audioPlaying) {
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                  height: 110,
                  child: Image.asset('assets/branding/lily_cloud.png',
                      fit: BoxFit.cover,
                      semanticLabel: 'Smiling cloud nightlight')),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 6),
                        DeviceStatusBadge(status: device.status),
                        const SizedBox(height: 10),
                        if (device.supportsLight ||
                            device.hasCapability('power'))
                          SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonal(
                                  onPressed: device.online && !sendingPower
                                      ? () => _switchPower(context)
                                      : null,
                                  child: Text(
                                      sendingPower
                                          ? 'Sending...'
                                          : (device.supportsLight
                                                  ? device.lightEnabled
                                                  : device.genericState[
                                                          'enabled'] ==
                                                      true)
                                              ? 'Turn off'
                                              : 'Turn on',
                                      textAlign: TextAlign.center))),
                        if (device.supportsAudio)
                          SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                  onPressed: device.online && device.audioLoaded
                                      ? () => _play(context)
                                      : null,
                                  child: Text(
                                      device.audioPlaying ? 'Stop' : 'Play'))),
                        SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                                onPressed: () => _open(context),
                                icon: const Icon(Icons.tune, size: 18),
                                label: const Text('More'))),
                        if (device.supportsAudio && device.audioPlaying)
                          const Text('Music playing',
                              style: TextStyle(fontSize: 12)),
                      ])),
            ]),
      ),
    );
  }
}
