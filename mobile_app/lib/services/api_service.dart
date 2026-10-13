import 'dart:convert';
import 'dart:math';
import 'session_store.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/device.dart';
import '../models/music_track.dart';
import '../models/home.dart';

class ApiService {
  ApiService({http.Client? client, SessionStore? sessionStore})
      : _client = client ?? http.Client(),
        sessionStore = sessionStore ?? SecureSessionStore();

  final http.Client _client;
  String baseUrl = AppConfig.backendBaseUrl;
  String? token;
  void Function()? onSessionInvalidated;
  final SessionStore sessionStore;
  Map<String, dynamic>? _session;
  Future<void>? _refreshing;
  int _revision = 0;
  Future<void> _storageTail = Future<void>.value();
  Future<T> _storage<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  String? get sessionIdentity {
    try {
      final encoded = token!.split('.')[1];
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(encoded)))) as Map;
      return (payload['sid'] ?? payload['sub'])?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> createWidgetSession(String installationId) =>
      _jsonRequest('/widgets/session',
          method: 'POST', body: {'installation_id': installationId});

  bool _validSession(Map<String, dynamic> data) =>
      [
        'access_token',
        'refresh_token',
        'session_expires_at',
        'access_expires_at'
      ].every(
          (key) => data[key] is String && (data[key] as String).isNotEmpty) &&
      DateTime.tryParse(data['session_expires_at'] as String) != null &&
      DateTime.tryParse(data['access_expires_at'] as String) != null;
  void _checkRevision(int revision, String url) {
    if (revision != _revision || url != baseUrl)
      throw StateError('Session changed.');
  }

  Future<void> restoreSession() async {
    final rev = _revision, url = baseUrl;
    final stored = await _storage(() => sessionStore.read(url));
    _checkRevision(rev, url);
    if (stored != null && !_validSession(stored)) {
      await clearSession();
      throw ApiException(401, 'Saved login is invalid. Sign in again.');
    }
    _session = stored;
    token = _session?['access_token'] as String? ?? token;
    if (_session != null && _expired('session_expires_at')) {
      await clearSession();
      throw ApiException(401, 'Your session expired. Sign in again.');
    }
  }

  bool _expired(String field) =>
      DateTime.tryParse(_session?[field]?.toString() ?? '')
          ?.isAfter(DateTime.now().toUtc()) !=
      true;
  Future<void> clearSession() async {
    final url = baseUrl;
    _revision++;
    token = null;
    _session = null;
    onSessionInvalidated?.call();
    await _storage(() => sessionStore.clear(url));
  }

  Future<void> logoutSession() async {
    final old = _session?['refresh_token'];
    await clearSession();
    if (old != null) {
      try {
        await _jsonRequest('/auth/mobile/logout',
            method: 'POST', body: {'refresh_token': old});
      } catch (_) {}
    }
  }

  Future<void> _acceptSession(
          Map<String, dynamic> data, int revision, String url) =>
      _storage(() async {
        _checkRevision(revision, url);
        if (!_validSession(data))
          throw ApiException(502, 'Invalid login response from server.');
        await sessionStore.write(url, data);
        _checkRevision(revision, url);
        _session = Map<String, dynamic>.from(data);
        token = data['access_token'] as String;
      });

  Future<void> _refreshSession() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final future = _performRefresh();
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<void> _performRefresh() async {
    if (_session == null || _expired('session_expires_at')) {
      throw ApiException(401, 'Your session expired. Sign in again.');
    }
    final rev = _revision;
    final url = baseUrl;
    _session!['refresh_request_id'] ??= List.generate(
            24,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final pending = Map<String, dynamic>.from(_session!);
    await _storage(() async {
      _checkRevision(rev, url);
      await sessionStore.write(url, pending);
    });
    _checkRevision(rev, url);
    final response = await _client
        .post(Uri.parse('$url/auth/mobile/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'refresh_token': pending['refresh_token'],
              'request_id': pending['refresh_request_id']
            }))
        .timeout(const Duration(seconds: 10));
    if (rev != _revision || url != baseUrl) {
      throw StateError('Session changed.');
    }
    if (response.statusCode == 401) {
      await clearSession();
      throw ApiException(401, 'Your session expired. Sign in again.');
    }
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, 'Could not refresh login. Try again.');
    }
    await _acceptSession(
        (jsonDecode(response.body) as Map).cast<String, dynamic>(), rev, url);
  }

  Future<http.Response> _send(String method, String path,
      {Object? body, bool retry = true}) async {
    final rev = _revision;
    final url = baseUrl;
    if (_session != null && _expired('access_expires_at')) {
      await _refreshSession();
    }
    _checkRevision(rev, url);
    final request = http.Request(method, Uri.parse('$url$path'))
      ..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
            await _client.send(request).timeout(const Duration(seconds: 10)))
        .timeout(const Duration(seconds: 10));
    if (rev != _revision) throw StateError('Session changed.');
    if (response.statusCode == 401 && retry && _session != null) {
      await _refreshSession();
      _checkRevision(rev, url);
      return _send(method, path, body: body, retry: false);
    }
    if (response.statusCode == 401 && _session != null) await clearSession();
    return response;
  }

  Future<String> loginMobile(String email, String password) async {
    final rev = _revision, url = baseUrl;
    final data = await _jsonRequest('/auth/mobile/login',
        method: 'POST', body: {'email': email, 'password': password});
    await _acceptSession(data, rev, url);
    return data['access_token'] as String;
  }

  Future<String> registerMobile(
      String email, String password, String firstName, String lastName) async {
    final rev = _revision, url = baseUrl;
    final data =
        await _jsonRequest('/auth/mobile/register', method: 'POST', body: {
      'email': email,
      'password': password,
      'first_name': firstName.isEmpty ? null : firstName,
      'last_name': lastName.isEmpty ? null : lastName
    });
    await _acceptSession(data, rev, url);
    return data['access_token'] as String;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _jsonRequest(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final response = await _send(method, path, body: body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed (${response.statusCode})';

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          final detail = decoded['detail'];

          if (detail is String) {
            message = detail;
          } else if (detail is List) {
            final messages = detail.map((error) {
              if (error is Map<String, dynamic>) {
                final loc = error['loc'];
                String field = '';

                if (loc is List && loc.isNotEmpty) {
                  field = loc.last.toString();
                }

                final msg = error['msg']?.toString() ?? 'Invalid value';
                return field.isNotEmpty ? '$field: $msg' : msg;
              }

              return error.toString();
            }).join('\n');

            if (messages.isNotEmpty) {
              message = messages;
            }
          }
        }
      } catch (_) {
        // Keep the status-code fallback when the server response is not JSON.
      }

      throw ApiException(response.statusCode, message);
    }

    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String> login(String email, String password) async {
    final data = await _jsonRequest(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
    );
    return data['access_token'] as String;
  }

  Future<String> register(
    String email,
    String password,
    String firstName,
    String lastName,
  ) async {
    final data = await _jsonRequest(
      '/auth/register',
      method: 'POST',
      body: {
        'email': email,
        'password': password,
        'first_name': firstName.isEmpty ? null : firstName,
        'last_name': lastName.isEmpty ? null : lastName,
      },
    );
    return data['access_token'] as String;
  }

  Future<Map<String, dynamic>> me() => _jsonRequest('/auth/me');
  Future<Map<String, dynamic>> removeDevice(int id) =>
      _jsonRequest('/devices/$id/removal', method: 'POST');
  Future<Map<String, dynamic>> getDeviceOperation(String id) =>
      _jsonRequest('/device-operations/$id');
  Future<Map<String, dynamic>> createWifiSession(int id, String challenge) =>
      _jsonRequest('/devices/$id/wifi-session',
          method: 'POST', body: {'challenge': challenge});
  Future<Map<String, dynamic>> createResetAuthorization(
          String id, String challenge, {bool completion = false}) =>
      _jsonRequest(
          '/device-operations/$id/${completion ? 'completion-authorization' : 'ble-authorization'}',
          method: 'POST',
          body: {'challenge': challenge});
  Future<Map<String, dynamic>> submitResetReceipt(
          Map<String, dynamic> receipt) =>
      _jsonRequest('/device-runtime/reset-complete',
          method: 'POST', body: {'receipt': receipt});

  Future<List<Device>> getDevices() async {
    final response = await _send('GET', '/devices');
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          'Could not load devices (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((item) => Device.fromJson((item as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<String> createPairingToken() async {
    final data = await _jsonRequest('/devices/pairing-session', method: 'POST');
    return data['pairing_token'] as String;
  }

  Future<void> setDeviceState(int deviceId, Map<String, dynamic> state) async {
    await _jsonRequest('/devices/$deviceId/state',
        method: 'PUT', body: {'state': state});
  }

  Future<void> genericCommand(
      int deviceId, String type, Map<String, dynamic> payload) async {
    final result =
        await _jsonRequest('/devices/$deviceId/command', method: 'POST', body: {
      'type': type,
      'payload': payload,
    });
    _checkCommandPublished(result);
  }

  void _checkCommandPublished(Map<String, dynamic> result) {
    if (result['mqtt_published'] == false) {
      throw Exception(
          'Command could not be sent to MQTT. Check the backend broker connection and try again.');
    }
  }

  Future<void> setLight(
    int deviceId, {
    required bool enabled,
    int? brightness,
    int? r,
    int? g,
    int? b,
  }) async {
    final result = await _jsonRequest(
      '/devices/$deviceId/light',
      method: 'PUT',
      body: {
        'enabled': enabled,
        if (brightness != null) 'brightness': brightness,
        if (r != null) 'r': r,
        if (g != null) 'g': g,
        if (b != null) 'b': b,
      },
    );
    _checkCommandPublished(result);
  }

  Future<void> playAudio(int deviceId) async {
    await _jsonRequest('/devices/$deviceId/audio/play', method: 'POST');
  }

  Future<void> stopAudio(int deviceId) async {
    await _jsonRequest('/devices/$deviceId/audio/stop', method: 'POST');
  }

  Future<void> setVolume(int deviceId, int volume) async {
    await _jsonRequest(
      '/devices/$deviceId/audio/volume',
      method: 'PUT',
      body: {'volume': volume},
    );
  }

  Future<List<MusicTrack>> getMusic() async {
    final response = await _send('GET', '/music');
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, 'Could not load music (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((item) =>
            MusicTrack.fromJson((item as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Uint8List> downloadMusic(int musicId) async {
    final response = await _send('GET', '/music/$musicId/download');
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          'Music download failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> getSchedules(int deviceId) async {
    final response = await _send('GET', '/schedules/device/$deviceId');
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          'Could not load schedules (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> createSchedule({
    required int deviceId,
    required String name,
    required String time,
    required List<int> days,
    required Map<String, dynamic> action,
  }) async {
    await _jsonRequest(
      '/schedules/device/$deviceId',
      method: 'POST',
      body: {
        'name': name,
        'time_of_day': time,
        'days_of_week': days,
        'action': action,
        'enabled': true,
      },
    );
  }

  Future<void> deleteSchedule(int scheduleId) async {
    await _jsonRequest('/schedules/$scheduleId', method: 'DELETE');
  }

  Future<List<LilyHome>> getHomes() async {
    final response = await _send('GET', '/homes');
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          _messageFromResponse(response, 'Could not load homes'));
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => LilyHome.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<LilyRoom>> getRooms(int homeId) async {
    final response = await _send('GET', '/homes/$homeId/rooms');
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          _messageFromResponse(response, 'Could not load rooms'));
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => LilyRoom.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> createHome(String name) async {
    await _jsonRequest('/homes',
        method: 'POST', body: {'name': name, 'timezone': 'Europe/Paris'});
  }

  Future<void> renameHome(int homeId, String name) async {
    await _jsonRequest('/homes/$homeId', method: 'PATCH', body: {'name': name});
  }

  Future<void> deleteHome(int homeId) async {
    await _jsonRequest('/homes/$homeId', method: 'DELETE');
  }

  Future<void> createRoom(int homeId, String name) async {
    await _jsonRequest('/homes/$homeId/rooms',
        method: 'POST', body: {'name': name});
  }

  Future<void> renameRoom(int roomId, String name) async {
    await _jsonRequest('/rooms/$roomId', method: 'PATCH', body: {'name': name});
  }

  Future<void> deleteRoom(int roomId) async {
    await _jsonRequest('/rooms/$roomId', method: 'DELETE');
  }

  Future<void> moveDevice(int deviceId,
      {required int? homeId, required int? roomId}) async {
    await _jsonRequest('/devices/$deviceId/profile',
        method: 'PUT', body: {'home_id': homeId, 'room_id': roomId});
  }

  Future<void> renameDevice(int deviceId, String name) async {
    await _jsonRequest('/devices/$deviceId',
        method: 'PATCH', body: {'name': name.trim()});
  }

  String _messageFromResponse(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}
