import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/main.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/models/home.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/widgets/device_card.dart';
import 'package:lily_mobile/widgets/lily_logo.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('V6 cloud home and blue controls remain visible at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState();
      state.api.token = 'theme-verification-only';
      state.homes = [
        const LilyHome(id: 1, name: 'My Home', timezone: 'Europe/Paris')
      ];
      state.rooms = [
        const LilyRoom(id: 1, homeId: 1, name: 'testing', icon: null)
      ];
      state.devices = [
        Device.fromJson({
          'id': 1,
          'serial_number': 'THEME-TEST',
          'name': 'Lily Audio Light',
          'online': true,
          'status': 'ONLINE',
          'smart_home': {'home_id': 1, 'room_id': 1},
        })
      ];
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state, child: const LilyApp()));
      await tester.pumpAndSettle();
      expect(find.byType(LilyLogo), findsOneWidget);
      expect(find.text('A little everyday magic'), findsOneWidget);
      expect(find.text('Lights, music, and cozy moments with Lily.'),
          findsOneWidget);
      expect(find.text('Devices are grouped by home and room.'), findsNothing);
      expect(find.text('My devices'), findsOneWidget);
      expect(find.byType(DeviceCard), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.byTooltip('Home configuration'), findsOneWidget);
      final button = find.ancestor(
          of: find.text('Turn on'), matching: find.byType(FilledButton));
      expect(button, findsOneWidget);
      final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first);
      expect(material.color, const Color(0xFFDCEFFC),
          reason: 'Preserve the pale-blue device control from the V6 reference.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
}
