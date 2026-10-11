import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/music_track.dart';
import '../models/home.dart';
import '../services/api_service.dart';
import '../models/backend_settings.dart';

class AppState extends ChangeNotifier {
  AppState({ApiService? api}) : api = api ?? ApiService();
  final ApiService api;
  int _sessionRevision = 0;
  BackendSettings get backendSettings => BackendSettings.fromUrl(api.baseUrl);

  Future<void> saveBackendSettings(BackendSettings settings) async {
    if (busy) throw StateError('Wait for the current request to finish.');
    final prefs = await SharedPreferences.getInstance();
    final changed = settings.baseUrl != backendSettings.baseUrl;
    // Remove the old server's persisted token before persisting a new server.
    if (changed) await logout();
    if (!await prefs.setString('backend_base_url', settings.baseUrl)) {
      throw StateError('Could not save backend settings.');
    }
    if (changed) {
      api.baseUrl = settings.baseUrl;
      error = null;
    }
    notifyListeners();
  }

  bool initialized = false;
  bool busy = false;
  String? error;
  Map<String, dynamic>? profile;
  List<Device> devices = [];
  List<MusicTrack> music = [];
  List<LilyHome> homes = [];
  List<LilyRoom> rooms = [];
  bool offline = false;

  Future<void> _cacheSession() async {
    final revision = _sessionRevision;
    final prefs = await SharedPreferences.getInstance();
    if (revision != _sessionRevision || !authenticated) return;
    await prefs.setString(
        'session_cache',
        jsonEncode({
          'server': api.baseUrl,
          'token': api.token,
          'profile': profile,
          'devices': devices.map((d) => d.toJson()).toList(),
          'homes': homes
              .map((h) => {'id': h.id, 'name': h.name, 'timezone': h.timezone})
              .toList(),
          'rooms': rooms
              .map((r) => {
                    'id': r.id,
                    'home_id': r.homeId,
                    'name': r.name,
                    'icon': r.icon
                  })
              .toList(),
          'music': music
              .map((m) => {
                    'id': m.id,
                    'title': m.title,
                    'description': m.description,
                    'filename': m.filename,
                    'filesize': m.filesize,
                    'checksum_sha256': m.checksum
                  })
              .toList(),
        }));
  }

  void _restoreSession(String? saved) {
    if (saved == null) return;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      if (data['server'] != api.baseUrl || data['token'] != api.token) return;
      final cachedDevices = (data['devices'] as List)
          .map((d) => Device.fromJson({
                ...Map<String, dynamic>.from(d as Map),
                'online': false,
                'status': 'OFFLINE',
              }))
          .toList();
      final cachedHomes = (data['homes'] as List)
          .map((h) => LilyHome.fromJson(Map<String, dynamic>.from(h as Map)))
          .toList();
      final cachedRooms = (data['rooms'] as List)
          .map((r) => LilyRoom.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      final cachedMusic = (data['music'] as List)
          .map((m) => MusicTrack.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
      profile = (data['profile'] as Map?)?.cast<String, dynamic>();
      devices = cachedDevices;
      homes = cachedHomes;
      rooms = cachedRooms;
      music = cachedMusic;
      offline = true;
    } catch (_) {
      // Ignore incomplete or corrupt cache; the saved login can still reconnect.
    }
  }

  bool get authenticated => api.token != null;

  bool _savedTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      final expires = payload['exp'];
      return expires is num &&
          expires <= DateTime.now().millisecondsSinceEpoch / 1000;
    } catch (_) {
      // The server remains responsible for token integrity and validation.
      return false;
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('backend_base_url');
    if (savedUrl != null) {
      try {
        api.baseUrl = BackendSettings.fromUrl(savedUrl).baseUrl;
      } on FormatException {
        await prefs.remove('backend_base_url');
      }
    }
    api.token = prefs.getString('access_token');

    if (api.token != null && _savedTokenExpired(api.token!)) {
      await logout();
    }

    if (api.token != null) {
      _restoreSession(prefs.getString('session_cache'));
      try {
        profile = await api.me();
        await refresh();
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) {
          await logout();
        } else {
          offline = true;
          error = 'Unable to connect. Showing saved configuration.';
        }
      }
    }

    initialized = true;
    notifyListeners();
  }

  Future<void> _storeToken(String token) async {
    api.token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  Future<void> login(String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final token = await api.login(email, password);
      await _storeToken(token);
      profile = await api.me();
      await refresh();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> register(
    String email,
    String password,
    String firstName,
    String lastName,
  ) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final token = await api.register(email, password, firstName, lastName);
      await _storeToken(token);
      profile = await api.me();
      await refresh();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _sessionRevision++;
    api.token = null;
    profile = null;
    devices = [];
    music = [];
    homes = [];
    rooms = [];
    offline = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_cache');
    if (!await prefs.remove('access_token')) {
      throw StateError('Could not clear the saved session.');
    }
  }

  Future<void> refresh() async {
    final revision = _sessionRevision;
    try {
      await _refresh();
    } catch (e) {
      if (revision != _sessionRevision) return;
      if (e is ApiException && e.statusCode == 401) {
        await logout();
      } else {
        offline = true;
        error = 'Unable to connect. Pull down to try again.';
        devices = devices
            .map((d) => Device.fromJson(
                {...d.toJson(), 'online': false, 'status': 'OFFLINE'}))
            .toList();
        notifyListeners();
      }
    }
  }

  Future<void> _refresh() async {
    if (!authenticated) return;
    final revision = _sessionRevision;
    final loadedDevices = await api.getDevices();
    if (revision != _sessionRevision) return;
    final loadedMusic = await api.getMusic();
    if (revision != _sessionRevision) return;
    final loadedHomes = await api.getHomes();
    if (revision != _sessionRevision) return;
    final loadedRooms = <LilyRoom>[];
    for (final home in loadedHomes) {
      loadedRooms.addAll(await api.getRooms(home.id));
      if (revision != _sessionRevision) return;
    }
    devices = loadedDevices;
    music = loadedMusic;
    homes = loadedHomes;
    rooms = loadedRooms;
    offline = false;
    error = null;
    await _cacheSession();
    notifyListeners();
  }
}
