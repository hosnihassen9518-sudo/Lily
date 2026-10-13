import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/screens/device_configuration_screen.dart';
import 'package:lily_mobile/screens/music_screen.dart';
import 'package:lily_mobile/models/home.dart';
import 'package:lily_mobile/models/music_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/screens/device_screen.dart';
import 'package:lily_mobile/state/app_state.dart';

Device device(List<String> caps) => Device.fromJson({
      'id': 1,
      'serial_number': 'cloud',
      'name': 'Bedroom cloud',
      'online': true,
      'smart_home': {'capabilities': caps}
    });
void main() {
  test(
      'Light API omits absent brightness and RGB while preserving explicit values',
      () async {
    final bodies = <Map>[];
    final api = ApiService(client: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return http.Response('{"mqtt_published":true}', 200);
    }));
    await api.setLight(1, enabled: true);
    await api.setLight(1, enabled: false, brightness: 0);
    await api.setLight(1, enabled: true, r: 0, g: 1, b: 2);
    expect(bodies, [
      {'enabled': true},
      {'enabled': false, 'brightness': 0},
      {'enabled': true, 'r': 0, 'g': 1, 'b': 2}
    ]);
  });
  testWidgets(
      'Music installation is disabled without an explicitly audio device',
      (tester) async {
    final state = AppState()
      ..devices = [
        device([]),
        device(['light'])
      ]
      ..music = [
        MusicTrack.fromJson({'id': 1, 'title': 'Cloud song'})
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: MusicScreen()))));
    expect(find.text('Add an audio-capable Lily device to install music.'),
        findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Install'));
    expect(button.onPressed, isNull);
  });
  testWidgets(
      'Configuration saves rename and Location then requires removal confirmation',
      (tester) async {
    final mutations = <http.Request>[];
    final api = ApiService(client: MockClient((request) async {
      if (request.method != 'GET') {
        mutations.add(request);
        return http.Response('{}', 200);
      }
      return http.Response('[]', 200);
    }));
    final state = AppState(api: api)
      ..devices = [
        device(['light'])
      ]
      ..homes = [
        const LilyHome(id: 1, name: 'Family home', timezone: 'Europe/Paris')
      ]
      ..rooms = [const LilyRoom(id: 2, homeId: 1, name: 'Bedroom', icon: null)];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child:
            const MaterialApp(home: DeviceConfigurationScreen(deviceId: 1))));
    await tester.tap(find.text('Rename device'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' New cloud ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(mutations.single.method, 'PATCH');
    expect(jsonDecode(mutations.single.body), {'name': 'New cloud'});
    // Refresh has no login in this fixture; keep the test device while verifying the independent placement request.
    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<int?>).first);
    await tester.tap(find.byType(DropdownButtonFormField<int?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family home').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(mutations.last.body), {'home_id': 1, 'room_id': null});
    expect(mutations.last.url.path, endsWith('/devices/1/profile'));
    await tester.ensureVisible(find.text('Remove device'));
    await tester.tap(find.text('Remove device'));
    await tester.pumpAndSettle();
    expect(mutations.where((r) => r.url.path.endsWith('/removal')), isEmpty);
    await tester.tap(find.text('Remove and reset'));
    await tester.pumpAndSettle();
    expect(find.text('Remove and reset device?'), findsOneWidget);
    expect(mutations.where((r) => r.url.path.endsWith('/removal')), isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  test('Unknown models grant no controls', () {
    final d = device([]);
    expect(d.supportsLight, false);
    expect(d.supportsAudio, false);
    expect(d.hasCapability('brightness'), false);
  });
  for (final caps in <List<String>>[
    [],
    ['light'],
    ['light', 'brightness'],
    ['light', 'rgb'],
    ['audio'],
    ['audio', 'volume'],
    ['light', 'brightness', 'rgb', 'audio', 'volume'],
    ['power']
  ]) {
    testWidgets('Explicit controls for $caps and isolated configuration',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState()..devices = [device(caps)];
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.5)),
                  child: child!),
              home: const DeviceScreen(deviceId: 1))));
      expect(find.text('Light'),
          caps.contains('light') ? findsOneWidget : findsNothing);
      expect(find.text('Music'),
          caps.contains('audio') ? findsOneWidget : findsNothing);
      expect(find.text('Brightness: 100%'),
          caps.contains('brightness') ? findsOneWidget : findsNothing);
      expect(find.text('Color'),
          caps.contains('rgb') ? findsOneWidget : findsNothing);
      expect(find.text('Volume: 50%'),
          caps.contains('volume') ? findsOneWidget : findsNothing);
      expect(
          find.text('Power'),
          caps.contains('power') && !caps.contains('light')
              ? findsOneWidget
              : findsNothing);
      expect(find.text('Location'), findsNothing);
      expect(find.text('Remove device'), findsNothing);
      expect(find.byTooltip('Rename device'), findsNothing);
      await tester.ensureVisible(find.text('Configuration'));
      await tester.tap(find.text('Configuration'));
      await tester.pumpAndSettle();
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Rename device'), findsOneWidget);
      expect(find.text('Information'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove device'));
      expect(find.text('Remove device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
