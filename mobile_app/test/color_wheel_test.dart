import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lily_mobile/widgets/color_wheel.dart';

void main() {
  testWidgets(
      'wheel selects saturated red at its right edge and white at center',
      (tester) async {
    Color? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 240,
                child: ColorWheel(
                    color: Colors.white, onChanged: (v) => selected = v)))));
    final wheel = find.byType(CustomPaint).last;
    final center = tester.getCenter(wheel);
    await tester.tapAt(center + const Offset(108, 0));
    expect(HSVColor.fromColor(selected!).hue, closeTo(0, 2));
    expect(HSVColor.fromColor(selected!).saturation, closeTo(1, .02));
    await tester.tapAt(center);
    expect(selected, Colors.white);
  });
  testWidgets('disabled wheel ignores gestures', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body:
                SizedBox(width: 240, child: ColorWheel(color: Colors.white)))));
    expect(find.bySemanticsLabel('LED color wheel'), findsOneWidget);
  });
}
