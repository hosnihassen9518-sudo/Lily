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

Device device(List<String> caps) => Device.fromJson({
      'id': 1,
      'serial_number': 'CLOUD',
      'smart_home': {'capabilities': caps}
    });
void main() {
  for (final removed in [false, true]) {
    testWidgets(
        'Schedule dialog follows changed model features, removed=$removed',
        (tester) async {
      final requests = <Map>[];
      final api = ApiService(client: MockClient((request) async {
        if (request.method == 'POST') {
          requests.add(jsonDecode(request.body) as Map);
          return http.Response('{}', 200);
        }
        return http.Response('[]', 200);
      }));
      final initial = device(['light', 'audio']);
      final state = AppState(api: api)..devices = [initial];
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(home: SchedulesScreen(device: initial))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Play audio'), findsOneWidget);
      await tester.ensureVisible(find.text('Play audio'));
      await tester.tap(find.text('Play audio'));
      state.devices = removed
          ? []
          : [
              device(['light'])
            ];
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Play audio'), findsNothing);
      if (removed) {
        expect(find.text('Device not found'), findsWidgets);
        expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
                .onPressed,
            isNull);
        expect(requests, isEmpty);
        await tester.tap(find.text('Cancel'));
      } else {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(requests.single['action'], {
          'light': {'enabled': true}
        });
        state.devices = [device([])];
        state.notifyListeners();
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<FloatingActionButton>(find.byType(FloatingActionButton))
                .onPressed,
            isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
