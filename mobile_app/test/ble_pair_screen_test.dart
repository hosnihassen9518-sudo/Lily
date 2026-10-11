import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/screens/pair_device_screen.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/services/ble_provision_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'ble_provision_service_test.dart' show FakeTransport;

class DelayedScan extends FakeTransport {
  final result = Completer<List<BleSetupDevice>>();
  @override
  Future<List<BleSetupDevice>> scan() => result.future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'Leaving BLE discovery cancels without updating a disposed screen',
      (tester) async {
    final transport = DelayedScan();
    final service = BleProvisionService(transport: transport);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: AppState(),
        child: MaterialApp(home: PairDeviceScreen(provisionService: service))));
    await tester.pumpWidget(const SizedBox());
    transport.result.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(transport.connected, isFalse);
  });

  testWidgets('Finalization retry does not send Wi-Fi credentials again',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tokens = 0;
    var renameAttempts = 0;
    final api = ApiService(client: MockClient((request) async {
      if (request.url.path.endsWith('/pairing-session')) {
        tokens++;
        return http.Response('{"pairing_token":"token"}', 200);
      }
      if (request.method != 'GET') {
        renameAttempts++;
        return renameAttempts == 1
            ? http.Response('{"detail":"temporary failure"}', 500)
            : http.Response('{}', 200);
      }
      if (request.url.path.endsWith('/devices')) {
        return http.Response('[{"id":1,"serial_number":"test"}]', 200);
      }
      return http.Response('[]', 200);
    }))
      ..token = 'login-token';
    final state = AppState(api: api);
    final service = BleProvisionService(
        transport: FakeTransport(), pollInterval: Duration.zero);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          final added = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                  builder: (_) => PairDeviceScreen(
                                      provisionService: service)));
                          if (context.mounted && added == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Device added successfully')));
                          }
                        },
                        child: const Text('Home - add device')))))));
    await tester.tap(find.text('Home - add device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi networks seen by ESP32'), findsOneWidget);
    await tester.tap(find.text('Connect and add device'));
    await tester.pumpAndSettle();
    expect(find.text('Retry finishing setup'), findsOneWidget);
    await tester.tap(find.text('Retry finishing setup'));
    await tester.pumpAndSettle();
    expect(find.text('Home - add device'), findsOneWidget);
    expect(find.text('Device added successfully'), findsOneWidget);
    expect(find.text('Add a Lily device'), findsNothing);
    expect(tokens, 1);
    expect(renameAttempts, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
