import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Restart offline retains login and cached homes and devices', () async {
    final api = ApiService(client: MockClient((request) async {
      final path = request.url.path;
      return http.Response(
          jsonEncode(path.endsWith('/auth/login')
              ? {'access_token': 'saved-token'}
              : path.endsWith('/auth/me')
                  ? {'email': 'parent@example.com'}
                  : path.endsWith('/devices')
                      ? [
                          {'id': 1, 'serial_number': 'cloud', 'online': true}
                        ]
                      : path.endsWith('/homes')
                          ? [
                              {'id': 1, 'name': 'Our home'}
                            ]
                          : path.endsWith('/rooms')
                              ? [
                                  {'id': 2, 'home_id': 1, 'name': 'Bedroom'}
                                ]
                              : []),
          200);
    }));
    await AppState(api: api).login('parent@example.com', 'password');
    final restored = AppState(api: ApiService(client: MockClient((_) async {
      throw http.ClientException('Offline');
    })));
    await restored.initialize();
    expect(restored.authenticated, isTrue);
    expect(restored.profile?['email'], 'parent@example.com');
    expect(restored.homes.single.name, 'Our home');
    expect(restored.rooms.single.name, 'Bedroom');
    expect(restored.devices.single.serial, 'cloud');
    expect(restored.devices.single.online, isFalse);
    await restored.logout();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getString('session_cache'), isNull);
  });

  test('Rejected saved token clears session and cache', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'expired'});
    final state = AppState(
        api: ApiService(
            client: MockClient(
                (_) async => http.Response('{"detail":"Expired"}', 401))));
    await state.initialize();
    expect(state.authenticated, isFalse);
  });

  test('An expired JWT requires login even while offline', () async {
    final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': 1})));
    SharedPreferences.setMockInitialValues(
        {'access_token': 'header.$payload.signature'});
    var requested = false;
    final state = AppState(api: ApiService(client: MockClient((_) async {
      requested = true;
      throw http.ClientException('Offline');
    })));
    await state.initialize();
    expect(state.authenticated, isFalse);
    expect(requested, isFalse);
    expect((await SharedPreferences.getInstance()).getString('access_token'),
        isNull);
  });
}
