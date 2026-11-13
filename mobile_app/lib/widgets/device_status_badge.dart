import 'package:flutter/material.dart';

class DeviceStatusBadge extends StatelessWidget {
  final String status;
  const DeviceStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color color = switch (normalized) {
      'ONLINE' => dark ? const Color(0xFF86E1AC) : const Color(0xFF24643E),
      'DISABLED' => dark ? const Color(0xFFFFB4AB) : const Color(0xFFA52A28),
      'INVENTORY' => Theme.of(context).colorScheme.onSurfaceVariant,
      _ => dark ? const Color(0xFFFFCB88) : const Color(0xFF874A00),
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
