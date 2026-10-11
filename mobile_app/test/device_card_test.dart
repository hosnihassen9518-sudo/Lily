import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/widgets/device_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Home light control sends on then off without opening device',
      (tester) async {
    var enabled = false;
    final commands = <bool>[];
    Map<String, dynamic> device() => {
          'id': 1,
          'serial_number': 'test',
          'online': true,
          'light': {'enabled': enabled},
          'smart_home': {
            'capabilities': ['power', 'light']
          },
        };
    final api = ApiService(client: MockClient((request) async {
      if (request.method == 'PUT') {
        expect(request.url.path, endsWith('/devices/1/light'));
        enabled = (jsonDecode(request.body) as Map)['enabled'] as bool;
        commands.add(enabled);
        return http.Response('{"mqtt_published":true}', 200);
      }
      return http.Response(
          request.url.path.endsWith('/devices') ? jsonEncode([device()]) : '[]',
          200);
    }));
    api.token = 'login-token';
    final state = AppState(api: api)..devices = [Device.fromJson(device())];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => DeviceCard(
                        device: context.watch<AppState>().devices.first))))));
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(commands, [true]);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(commands, [true, false]);
    expect(find.text('Turn on'), findsOneWidget);
  });

  testWidgets('Power-only devices retain a quick off control', (tester) async {
    final commands = <Map<String, dynamic>>[];
    final device = Device.fromJson({
      'id': 2,
      'serial_number': 'plug',
      'online': true,
      'smart_home': {
        'capabilities': ['power']
      },
    });
    final api = ApiService(client: MockClient((request) async {
      if (request.method == 'POST') {
        commands.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"mqtt_published":true}', 200);
      }
      return http.Response('[]', 200);
    }))
      ..token = 'saved';
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: AppState(api: api),
        child: MaterialApp(
            home: Scaffold(
                body:
                    SizedBox(width: 180, child: DeviceCard(device: device))))));
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(commands.single, {
      'type': 'power',
      'payload': {'enabled': false}
    });
  });

  test('Light and power commands report failed MQTT publishing', () async {
    final api = ApiService(
        client: MockClient(
            (_) async => http.Response('{"mqtt_published":false}', 200)));
    await expectLater(
        api.setLight(1,
            enabled: false, brightness: 100, r: 255, g: 255, b: 255),
        throwsA(isA<Exception>()));
    await expectLater(api.genericCommand(1, 'power', {'enabled': false}),
        throwsA(isA<Exception>()));
  });
}
