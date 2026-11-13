import 'package:flutter/material.dart';
import '../models/device.dart';

class DevicePicture extends StatelessWidget {
  const DevicePicture({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final key = device.productImageKey;
    final speaker = switch (key) {
      'lily-speaker' || 'gaming-speaker' => true,
      'lily-light' || 'gaming-light' => false,
      _ => device.supportsAudio,
    };
    final gaming = key == 'gaming-light' ||
        key == 'gaming-speaker' ||
        (key != 'lily-light' &&
            key != 'lily-speaker' &&
            device.appearanceKey == 'gaming');
    final light = key == 'lily-light' || device.supportsLight;
    if (gaming || (!speaker && !light)) {
      return Semantics(
        image: true,
        label: device.catalogName,
        child: ColoredBox(
          color: gaming ? const Color(0xFF1C2B47) : const Color(0xFFE8E3F4),
          child: Center(
            child: Icon(
              gaming
                  ? (speaker ? Icons.speaker : Icons.lightbulb)
                  : Icons.devices_other,
              color: gaming ? const Color(0xFF75E9DD) : const Color(0xFF614B94),
              size: 48,
            ),
          ),
        ),
      );
    }
    return Semantics(
      image: true,
      label: speaker ? 'Lily nightlight with speaker' : 'Lily nightlight',
      excludeSemantics: true,
      child: ColoredBox(
        color: const Color(0xFFB7A8F0),
        child: Image.asset(
          speaker
              ? 'assets/branding/lily_speaker.png'
              : 'assets/branding/lily_cloud.png',
          fit: speaker ? BoxFit.contain : BoxFit.cover,
        ),
      ),
    );
  }
}
