import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/device.dart';
import '../models/music_track.dart';
import '../models/home.dart';

class ApiService {
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _jsonRequest(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}$path');
    late http.Response response;

    switch (method) {
      case 'POST':
        response = await http.post(uri, headers: _headers, body: jsonEncode(body));
        break;
      case 'PUT':
        response = await http.put(uri, headers: _headers, body: jsonEncode(body));
        break;
      case 'PATCH':
        response = await http.patch(uri, headers: _headers, body: jsonEncode(body));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: _headers);
        break;
      default:
        response = await http.get(uri, headers: _headers);
    }

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

      throw Exception(message);
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

  Future<List<Device>> getDevices() async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/devices');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Could not load devices (${response.statusCode})');
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
    await _jsonRequest('/devices/$deviceId/state', method: 'PUT', body: {'state': state});
  }

  Future<void> genericCommand(int deviceId, String type, Map<String, dynamic> payload) async {
    await _jsonRequest('/devices/$deviceId/command', method: 'POST', body: {
      'type': type,
      'payload': payload,
    });
  }

  Future<void> setLight(
    int deviceId, {
    required bool enabled,
    required int brightness,
    required int r,
    required int g,
    required int b,
  }) async {
    await _jsonRequest(
      '/devices/$deviceId/light',
      method: 'PUT',
      body: {
        'enabled': enabled,
        'brightness': brightness,
        'r': r,
        'g': g,
        'b': b,
      },
    );
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
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/music');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Could not load music (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((item) => MusicTrack.fromJson((item as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Uint8List> downloadMusic(int musicId) async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/music/$musicId/download');
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Music download failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> getSchedules(int deviceId) async {
    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/schedules/device/$deviceId',
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Could not load schedules (${response.statusCode})');
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
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/homes');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(_messageFromResponse(response, 'Could not load homes'));
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => LilyHome.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<LilyRoom>> getRooms(int homeId) async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/homes/$homeId/rooms');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(_messageFromResponse(response, 'Could not load rooms'));
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => LilyRoom.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> createHome(String name) async {
    await _jsonRequest('/homes', method: 'POST', body: {'name': name, 'timezone': 'Europe/Paris'});
  }

  Future<void> renameHome(int homeId, String name) async {
    await _jsonRequest('/homes/$homeId', method: 'PATCH', body: {'name': name});
  }

  Future<void> deleteHome(int homeId) async {
    await _jsonRequest('/homes/$homeId', method: 'DELETE');
  }

  Future<void> createRoom(int homeId, String name) async {
    await _jsonRequest('/homes/$homeId/rooms', method: 'POST', body: {'name': name});
  }

  Future<void> renameRoom(int roomId, String name) async {
    await _jsonRequest('/rooms/$roomId', method: 'PATCH', body: {'name': name});
  }

  Future<void> deleteRoom(int roomId) async {
    await _jsonRequest('/rooms/$roomId', method: 'DELETE');
  }

  Future<void> moveDevice(int deviceId, {required int? homeId, required int? roomId}) async {
    await _jsonRequest('/devices/$deviceId/profile', method: 'PUT', body: {'home_id': homeId, 'room_id': roomId});
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
