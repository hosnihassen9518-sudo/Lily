import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/screens/schedules_screen.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';

void main() {
  for (final typed in [false, true]) {
    for (final width in [320.0, 800.0]) {
      testWidgets(
          'Readable days and editing preserve schedule actions at $width typed=$typed',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final edits = <Map>[];
        final row = {
          'id': 7,
          'name': 'Bedtime',
          'time_of_day': '20:00:00',
          'days_of_week': [0, 2, 4],
          'enabled': true,
          'action': typed
              ? {
                  'type': 'light',
                  'payload': {'enabled': false}
                }
              : {
                  'light': {'enabled': true}
                }
        };
        final api = ApiService(client: MockClient((r) async {
          if (r.method == 'PATCH') {
            edits.add(jsonDecode(r.body));
            return http.Response('{}', 200);
          }
          return http.Response(jsonEncode([row]), 200);
        }));
        final d = Device.fromJson({
          'id': 1,
          'serial_number': 'TEST',
          'smart_home': {
            'capabilities': ['power', 'light']
          }
        });
        final state = AppState(api: api)..devices = [d];
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: state,
            child: MaterialApp(home: SchedulesScreen(device: d))));
        await tester.pumpAndSettle();
        expect(
            find.textContaining('Monday, Wednesday, Friday'), findsOneWidget);
        await tester.tap(find.text('Bedtime'));
        await tester.pumpAndSettle();
        expect(find.text('Edit schedule'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, 'Morning');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(edits.single['name'], 'Morning');
        expect(edits.single['days_of_week'], [0, 2, 4]);
        expect(edits.single['action'], {
          'light': {'enabled': !typed}
        });
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(edits.last['enabled'], false);
        await tester.tap(find.text('Bedtime'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Every day'));
        await tester.pumpAndSettle();
        for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
          await tester.ensureVisible(find.text(day));
          await tester.tap(find.text(day));
          await tester.pump();
        }
        expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
                .onPressed,
            isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final action in [
    {'type': 'audio_play', 'payload': <String, dynamic>{}},
    {
      'type': 'volume',
      'payload': {'volume': 30}
    },
  ]) {
    testWidgets('Editing ${action['type']} does not add light actions',
        (tester) async {
      Map? saved;
      final row = {
        'id': 8,
        'name': 'Sound',
        'time_of_day': '07:30:00',
        'days_of_week': [0],
        'enabled': true,
        'action': action
      };
      final api = ApiService(client: MockClient((request) async {
        if (request.method == 'PATCH') {
          saved = jsonDecode(request.body);
          return http.Response('{}', 200);
        }
        return http.Response(jsonEncode([row]), 200);
      }));
      final d = Device.fromJson({
        'id': 1,
        'serial_number': 'TEST',
        'smart_home': {
          'capabilities': ['power', 'light', 'audio', 'volume']
        }
      });
      final state = AppState(api: api)..devices = [d];
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state, child: MaterialApp(home: SchedulesScreen(device: d))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sound'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!['action'],
          action['type'] == 'volume' ? {'volume': 30} : {'audio': 'play'});
      expect(tester.takeException(), isNull);
    });
  }
}
