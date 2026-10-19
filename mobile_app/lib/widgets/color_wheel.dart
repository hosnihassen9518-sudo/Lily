import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Hue follows the angle; distance from the center controls saturation.
class ColorWheel extends StatelessWidget {
  final Color color;
  final ValueChanged<Color>? onChanged;
  final VoidCallback? onChangeEnd;
  const ColorWheel(
      {super.key, required this.color, this.onChanged, this.onChangeEnd});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LED color wheel',
      enabled: onChanged != null,
      child: Opacity(
        opacity: onChanged == null ? 0.4 : 1,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = math.min(240.0, constraints.maxWidth);
          void select(Offset point) {
            final delta = point - Offset(size / 2, size / 2);
            final hue =
                (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360;
            final saturation =
                (delta.distance / (size / 2 - 12)).clamp(0.0, 1.0);
            onChanged?.call(HSVColor.fromAHSV(1, hue, saturation, 1).toColor());
          }

          return Center(
              child: GestureDetector(
            onPanDown:
                onChanged == null ? null : (d) => select(d.localPosition),
            onPanUpdate:
                onChanged == null ? null : (d) => select(d.localPosition),
            onPanEnd: onChanged == null ? null : (_) => onChangeEnd?.call(),
            onPanCancel: onChanged == null ? null : () => onChangeEnd?.call(),
            onTapUp: onChanged == null ? null : (_) => onChangeEnd?.call(),
            child: CustomPaint(
                size: Size.square(size), painter: _WheelPainter(color)),
          ));
        }),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Color color;
  _WheelPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const colors = [
      Colors.red,
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Colors.red
    ];
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = const SweepGradient(colors: colors).createShader(rect));
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader =
              const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)])
                  .createShader(rect));
    final hsv = HSVColor.fromColor(color);
    final angle = hsv.hue * math.pi / 180;
    final point = center +
        Offset(math.cos(angle), math.sin(angle)) * (hsv.saturation * radius);
    canvas.drawCircle(point, 11, Paint()..color = Colors.black54);
    canvas.drawCircle(point, 8, Paint()..color = color);
    canvas.drawCircle(
        point,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.color != color;
}
