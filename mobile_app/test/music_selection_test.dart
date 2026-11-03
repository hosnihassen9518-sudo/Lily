import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/screens/device_screen.dart';
import 'package:lily_mobile/screens/music_screen.dart';
import 'package:lily_mobile/state/app_state.dart';

void main() {
  testWidgets('audio device offers a direct music-selection entry point',
      (tester) async {
    final state = AppState()
      ..devices = [
        Device.fromJson({
          'id': 7,
          'serial_number': 'audio',
          'online': true,
          'smart_home': {
            'capabilities': ['audio', 'volume']
          }
        })
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DeviceScreen(deviceId: 7))));
    await tester.scrollUntilVisible(find.text('Choose music'), 200);
    await tester.tap(find.text('Choose music'));
    await tester.pumpAndSettle();
    final screen = tester.widget<MusicScreen>(find.byType(MusicScreen));
    expect(screen.deviceId, 7);
    final scaffold = tester.widget<Scaffold>(find.descendant(
        of: find.byType(MusicScreen), matching: find.byType(Scaffold)));
    expect(scaffold.backgroundColor, const Color(0xFFF3EFFB));
    final pickerContext = tester.element(find.text('Search audio'));
    expect(Theme.of(pickerContext).brightness, Brightness.light);
    expect(Theme.of(pickerContext).colorScheme.onSurface,
        const Color(0xFF352C4A));
    expect(find.text('My files'), findsOneWidget);
    expect(find.text('Server catalog'), findsOneWidget);
    await tester.tap(find.text('My files'));
    await tester.pumpAndSettle();
    expect(find.text('Choose MP3 from phone'), findsOneWidget);
    await tester.tap(find.text('Server catalog'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('No music in the server catalog yet.'), 200,
        scrollable: find
            .descendant(
                of: find.byType(MusicScreen), matching: find.byType(Scrollable))
            .first);
    expect(find.text('No music in the server catalog yet.'), findsOneWidget);
  });
}
