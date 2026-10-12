import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/screens/device_management_screen.dart';

void main() {
  testWidgets(
      'Removal confirmation displays pending until confirmed by backend',
      (tester) async {
    var completed = false;
    final api = ApiService(client: MockClient((r) async {
      if (r.url.path.contains('/removal') ||
          r.url.path.contains('/device-operations/')) {
        return http.Response(
            jsonEncode({
              'operation_id': 'op',
              'device_id': 1,
              'status': completed ? 'completed' : 'pending'
            }),
            200);
      }
      return http.Response('[]', 200);
    }));
    api.token = 'test-token';
    final device = Device.fromJson(
        {'id': 1, 'serial_number': 'LILY-TEST', 'name': 'Bedroom'});
    final state = AppState(api: api)..devices = [device];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            home: DeviceManagementScreen(device: device, wifi: false))));
    await tester.tap(find.text('Remove and reset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saved Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Remove and reset').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Reset pending.'), findsOneWidget);
    expect(find.textContaining('account removal confirmed'), findsNothing);
    completed = true;
    await tester.tap(find.text('Check reset progress'));
    await tester.pumpAndSettle();
    expect(find.textContaining('account removal confirmed'), findsOneWidget);
    expect(state.devices, isEmpty);
  });
}
