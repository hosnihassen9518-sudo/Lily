import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lily_mobile/main.dart';
import 'package:lily_mobile/screens/home_screen.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/models/music_track.dart';
import 'package:lily_mobile/screens/music_screen.dart';
import 'package:lily_mobile/services/api_service.dart';

void main() {
  testWidgets('Native account exposes widget setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state, child: const MaterialApp(home: HomeScreen())));
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home-screen widgets'));
    await tester.pumpAndSettle();
    expect(find.text('Enable / refresh widgets'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('Login settings validates and saves the server', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.initialize();
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: state, child: const LilyApp()));
    await tester.tap(find.byTooltip('Backend settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'IP address or hostname'),
        '192.168.1.42');
    await tester.enterText(find.widgetWithText(TextFormField, 'Port'), '90001');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Port'), '6100');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.api.baseUrl, 'http://192.168.1.42:6100/api/v1');
    expect(find.text('Welcome to Lily'), findsOneWidget);
  });
  testWidgets('Main screen also exposes backend settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state, child: const MaterialApp(home: HomeScreen())));
    expect(find.byTooltip('Backend settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Leaving music while a download completes does not update a disposed screen',
      (tester) async {
    final download = Completer<http.Response>();
    final requested = Completer<void>();
    final state = AppState(api: ApiService(client: MockClient((request) {
      requested.complete();
      return download.future;
    })));
    state.devices = [
      Device.fromJson({
        'id': 1,
        'serial_number': 'test',
        'smart_home': {
          'capabilities': ['audio']
        }
      })
    ];
    state.music = [
      MusicTrack.fromJson({'id': 1, 'title': 'Test song'})
    ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: MusicScreen()))));
    await tester.tap(find.text('Install'));
    await requested.future;
    await tester.pumpWidget(const SizedBox());
    download.complete(http.Response('music', 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
