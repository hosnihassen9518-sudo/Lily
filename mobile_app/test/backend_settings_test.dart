import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lily_mobile/models/backend_settings.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Validates backend address and port', () {
    expect(
        BackendSettings.validated(
                host: 'lily.local', port: '443', scheme: 'https')
            .baseUrl,
        'https://lily.local:443/api/v1');
    expect(
        BackendSettings.validated(
                host: ' 192.168.1.42 ', port: '6100', scheme: 'http')
            .baseUrl,
        'http://192.168.1.42:6100/api/v1');
    for (final host in [
      '',
      'http://server',
      'server/path',
      'user@server',
      '256.1.1.1'
    ]) {
      expect(
          () => BackendSettings.validated(
              host: host, port: '6100', scheme: 'http'),
          throwsFormatException);
    }
    for (final port in ['0', '90001', '-1', 'abc']) {
      expect(
          () => BackendSettings.validated(
              host: 'server', port: port, scheme: 'http'),
          throwsFormatException);
    }
  });
  test('Changing servers persists settings and clears the old login', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'old-token'});
    final state = AppState();
    state.api.token = 'old-token';
    state.profile = {'email': 'old@example.com'};
    await state.saveBackendSettings(BackendSettings.validated(
        host: '192.168.1.42', port: '6100', scheme: 'http'));
    expect(state.authenticated, isFalse);
    expect(state.profile, isNull);
    expect((await SharedPreferences.getInstance()).getString('access_token'),
        isNull);
    final restarted = AppState();
    await restarted.initialize();
    expect(restarted.api.baseUrl, 'http://192.168.1.42:6100/api/v1');
  });
  test('Saving unchanged settings preserves the login', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.api.token = 'existing-token';
    await state.saveBackendSettings(state.backendSettings);
    expect(state.api.token, 'existing-token');
  });
  test('Loads the saved address before using a saved login token', () async {
    SharedPreferences.setMockInitialValues({
      'backend_base_url': 'http://saved-server.local:6100/api/v1',
      'access_token': 'saved-token',
    });
    final api = ApiService(client: MockClient((request) async {
      expect(request.url.host, 'saved-server.local');
      expect(request.headers['authorization'], 'Bearer saved-token');
      return http.Response(
          request.url.path.endsWith('/auth/me') ? '{}' : '[]', 200);
    }));
    final state = AppState(api: api);
    await state.initialize();
    expect(state.authenticated, isTrue);
  });
  test('All API request paths use the runtime backend', () async {
    final requests = <Uri>[];
    final api = ApiService(client: MockClient((request) async {
      requests.add(request.url);
      final path = request.url.path;
      return http.Response(
          jsonEncode(path.endsWith('/auth/login')
              ? {'access_token': 'new-token'}
              : path.endsWith('/auth/me')
                  ? {}
                  : []),
          200);
    }));
    api.baseUrl = 'http://192.168.1.42:6100/api/v1';
    await api.login('user@example.com', 'password');
    await api.me();
    await api.getDevices();
    await api.getMusic();
    await api.getSchedules(1);
    await api.getHomes();
    await api.getRooms(1);
    await api.downloadMusic(1);
    expect(requests, hasLength(8));
    expect(
        requests.every((uri) =>
            uri.host == '192.168.1.42' &&
            uri.port == 6100 &&
            uri.path.startsWith('/api/v1/')),
        isTrue);
  });
  test('A refresh from the previous server cannot overwrite new state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final api = ApiService(client: MockClient((request) {
      requested.complete();
      return response.future;
    }));
    api.token = 'old-token';
    final state = AppState(api: api);
    final refreshing = state.refresh();
    await requested.future;
    await state.saveBackendSettings(BackendSettings.validated(
        host: 'new-server.local', port: '6100', scheme: 'http'));
    response.complete(http.Response('[]', 200));
    await refreshing;
    expect(state.devices, isEmpty);
    expect(state.authenticated, isFalse);
    expect(state.api.baseUrl, 'http://new-server.local:6100/api/v1');
  });
}
