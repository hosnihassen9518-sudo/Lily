import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/screens/home_screen.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/theme/lily_theme.dart';
import 'package:lily_mobile/widgets/device_card.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('Two cards share a row at $width with large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState();
      state.api.token = 'saved';
      state.devices = List.generate(
          3,
          (i) => Device.fromJson({
                'id': i + 1,
                'serial_number': 'cloud-$i',
                'name': 'Bedroom cloud ${i + 1}',
                'online': false,
              }));
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
              theme: LilyTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.5)),
                  child: child!),
              home: const HomeScreen())));
      await tester.pumpAndSettle();
      final cards = find.byType(DeviceCard);
      expect(cards, findsNWidgets(3));
      final first = tester.getTopLeft(cards.at(0));
      final second = tester.getTopLeft(cards.at(1));
      final third = tester.getTopLeft(cards.at(2));
      expect(second.dy, first.dy);
      expect(second.dx, greaterThan(first.dx));
      expect(third.dy, greaterThan(first.dy));
      expect(find.byTooltip('Home configuration'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
