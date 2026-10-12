import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/services/session_store.dart';

class MemoryStore implements SessionStore {
  Map<String, dynamic>? data;
  @override
  Future<Map<String, dynamic>?> read(String url) async => data;
  @override
  Future<void> write(String url, Map<String, dynamic> value) async {
    data = value;
  }

  @override
  Future<void> clear(String url) async {
    data = null;
  }
}

class DelayedStore extends MemoryStore {
  final accepting = Completer<void>();
  final release = Completer<void>();
  int writes = 0;
  @override
  Future<void> write(String url, Map<String, dynamic> value) async {
    writes++;
    if (writes == 2) {
      accepting.complete();
      await release.future;
    }
    data = Map<String, dynamic>.from(value);
  }
}

void main() {
  test('Logout during refresh storage write cannot restore credentials',
      () async {
    final store = DelayedStore();
    final expiry =
        DateTime.now().add(const Duration(days: 90)).toUtc().toIso8601String();
    store.data = {
      'access_token': 'old',
      'refresh_token': 'r' * 64,
      'session_expires_at': expiry,
      'access_expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String()
    };
    final api = ApiService(
        sessionStore: store,
        client: MockClient((r) async => http.Response(
            jsonEncode({
              'access_token': 'new',
              'refresh_token': 's' * 64,
              'session_expires_at': expiry,
              'access_expires_at': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toUtc()
                  .toIso8601String()
            }),
            200)));
    await api.restoreSession();
    final refreshing = api.me();
    await store.accepting.future;
    final clearing = api.clearSession();
    store.release.complete();
    await clearing;
    try {
      await refreshing;
    } catch (_) {}
    expect(api.token, isNull);
    expect(store.data, isNull);
  });
  test('Backend change during refresh cannot dispatch old bearer to new host',
      () async {
    final store = DelayedStore();
    final expiry =
        DateTime.now().add(const Duration(days: 90)).toUtc().toIso8601String();
    store.data = {
      'access_token': 'old',
      'refresh_token': 'r' * 64,
      'session_expires_at': expiry,
      'access_expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String()
    };
    final requests = <http.Request>[];
    final api = ApiService(
        sessionStore: store,
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
              jsonEncode({
                'access_token': 'new',
                'refresh_token': 's' * 64,
                'session_expires_at': expiry,
                'access_expires_at': DateTime.now()
                    .add(const Duration(minutes: 15))
                    .toUtc()
                    .toIso8601String()
              }),
              200);
        }));
    await api.restoreSession();
    final refreshing = api.me();
    await store.accepting.future;
    final clearing = api.clearSession();
    api.baseUrl = 'https://new-server.test/api/v1';
    store.release.complete();
    await clearing;
    try {
      await refreshing;
    } catch (_) {}
    expect(api.token, isNull);
    expect(store.data, isNull);
    expect(requests.where((r) => r.url.host == 'new-server.test'), isEmpty);
  });
  test('Malformed saved session requests login without a startup TypeError',
      () async {
    final store = MemoryStore();
    store.data = {
      'access_token': 42,
      'refresh_token': [],
      'session_expires_at': {},
      'access_expires_at': true
    };
    final api = ApiService(sessionStore: store);
    await expectLater(api.restoreSession(), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
    expect(store.data, isNull);
  });
  test('Rejected session notifies the app to request authentication', () async {
    final store = MemoryStore();
    store.data = {
      'access_token': 'old',
      'refresh_token': 'r' * 64,
      'session_expires_at': DateTime.now()
          .add(const Duration(days: 90))
          .toUtc()
          .toIso8601String(),
      'access_expires_at': DateTime.now()
          .add(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String()
    };
    final api = ApiService(
        sessionStore: store,
        client: MockClient((_) async => http.Response('{}', 401)));
    var notifications = 0;
    api.onSessionInvalidated = () => notifications++;
    await api.restoreSession();
    await expectLater(api.me(), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
    expect(notifications, 1);
  });
  test(
      'Concurrent access expiry silently refreshes once without extending session',
      () async {
    final store = MemoryStore();
    final expiry =
        DateTime.now().add(const Duration(days: 90)).toUtc().toIso8601String();
    store.data = {
      'access_token': 'old',
      'refresh_token': 'r' * 64,
      'session_expires_at': expiry,
      'access_expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String()
    };
    var refreshes = 0;
    final api = ApiService(
        sessionStore: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/mobile/refresh')) {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return http.Response(
                jsonEncode({
                  ...store.data!,
                  'access_token': 'new',
                  'refresh_token': 's' * 64,
                  'access_expires_at': DateTime.now()
                      .add(const Duration(minutes: 15))
                      .toUtc()
                      .toIso8601String()
                }),
                200);
          }
          expect(r.headers['authorization'], 'Bearer new');
          return http.Response('{}', 200);
        }));
    await api.restoreSession();
    await Future.wait([api.me(), api.me()]);
    expect(refreshes, 1);
    expect(store.data!['session_expires_at'], expiry);
  });
}
