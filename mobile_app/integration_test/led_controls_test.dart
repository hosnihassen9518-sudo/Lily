import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/screens/device_screen.dart';
import 'package:lily_mobile/widgets/color_wheel.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('LED color wheel and brightness on Pixel emulator',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    final api = ApiService(client: MockClient((request) async {
      if (request.method == 'PUT') {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      return http.Response('{}', 200);
    }));
    final state = AppState(api: api)
      ..devices = [
        Device.fromJson({
          'id': 3,
          'serial_number': 'LED-EMULATOR-TEST',
          'name': 'Lily LED Strip 01',
          'online': true,
          'light': {
            'enabled': true,
            'brightness': 75,
            'r': 0,
            'g': 128,
            'b': 255
          },
          'smart_home': {
            'capabilities': ['power', 'light', 'brightness', 'rgb']
          }
        })
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DeviceScreen(deviceId: 3))));
    await tester.pumpAndSettle();
    expect(find.byType(ColorWheel), findsOneWidget);
    final wheel = find.byType(ColorWheel);
    final center = tester.getCenter(wheel);
    final gesture = await tester.startGesture(center + const Offset(90, 0));
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(center + Offset(90 - step * 7.0, step * 7.0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests.length, greaterThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests.length, greaterThan(1));
    expect(requests.last.keys,
        containsAll(['enabled', 'brightness', 'r', 'g', 'b']));
    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(-70, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2500)));
    await tester.pumpAndSettle();
    expect(requests.last['brightness'], lessThan(75));
    expect(tester.takeException(), isNull);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('lily-led-color-wheel');
  });
}
