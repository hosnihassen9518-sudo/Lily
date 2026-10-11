import 'package:flutter/material.dart';

class DeviceStatusBadge extends StatelessWidget {
  final String status;
  const DeviceStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase();
    final Color color = switch (normalized) {
      'ONLINE' => Colors.green,
      'DISABLED' => Colors.red,
      'INVENTORY' => Colors.grey,
      _ => Colors.orange,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
              child: Text(
            normalized,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          )),
        ],
      ),
    );
  }
}
