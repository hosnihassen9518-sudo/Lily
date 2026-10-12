import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/music_track.dart';
import '../models/home.dart';
import '../services/api_service.dart';
import '../services/widget_sync.dart';
import '../models/backend_settings.dart';

class AppState extends ChangeNotifier {
  AppState({ApiService? api, WidgetPlatform? widgetPlatform})
      : api = api ?? ApiService() {
    widgets = WidgetSync(this.api, platform: widgetPlatform);
    this.api.onSessionInvalidated = () {
      _sessionRevision++;
      profile = null;
      devices = [];
      music = [];
      homes = [];
      rooms = [];
      offline = false;
      unawaited(_clearCache());
      unawaited(widgets.clear());
      notifyListeners();
    };
  }

  @override
  void dispose() {
    api.onSessionInvalidated = null;
    super.dispose();
  }

  final ApiService api;
  late final WidgetSync widgets;
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

  bool offline = false;
  Future<void> _cacheTail = Future<void>.value();
  Future<void> _clearCache() {
    final next = _cacheTail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_cache');
    });
    _cacheTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _cacheSession() {
    final rev = _sessionRevision,
        url = api.baseUrl,
        identity = api.sessionIdentity;
    final snapshot = {
      'server': url,
      'session': identity,
      'profile': profile,
      'devices': devices.map((d) => d.toJson()).toList(),
      'homes': homes
          .map((h) => {'id': h.id, 'name': h.name, 'timezone': h.timezone})
          .toList(),
      'rooms': rooms
          .map((r) =>
              {'id': r.id, 'home_id': r.homeId, 'name': r.name, 'icon': r.icon})
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
          .toList()
    };
    final next = _cacheTail.then((_) async {
      if (rev != _sessionRevision || identity == null || !authenticated) return;
      final prefs = await SharedPreferences.getInstance();
      if (rev != _sessionRevision || url != api.baseUrl) return;
      await prefs.setString('session_cache', jsonEncode(snapshot));
    });
    _cacheTail = next.catchError((Object _) {});
    return next;
  }

  void _restoreCache(String? saved) {
    if (saved == null || api.sessionIdentity == null) return;
    try {
      final data = jsonDecode(saved) as Map;
      if (data['server'] != api.baseUrl ||
          data['session'] != api.sessionIdentity) return;
      final restored = (data['devices'] as List)
          .map((d) => Device.fromJson({
                ...Map<String, dynamic>.from(d),
                'online': false,
                'status':
                    d['status'] == 'RESET_PENDING' ? 'RESET_PENDING' : 'OFFLINE'
              }))
          .toList();
      final restoredHomes = (data['homes'] as List)
          .map((h) => LilyHome.fromJson(Map<String, dynamic>.from(h)))
          .toList();
      final restoredRooms = (data['rooms'] as List)
          .map((h) => LilyRoom.fromJson(Map<String, dynamic>.from(h)))
          .toList();
      final restoredMusic = (data['music'] as List)
          .map((h) => MusicTrack.fromJson(Map<String, dynamic>.from(h)))
          .toList();
      profile = (data['profile'] as Map?)?.cast<String, dynamic>();
      devices = restored;
      homes = restoredHomes;
      rooms = restoredRooms;
      music = restoredMusic;
      offline = true;
    } catch (_) {/* Corrupt cached data does not invalidate secure login. */}
  }

  bool initialized = false;
  bool busy = false;
  String? error;
  Map<String, dynamic>? profile;
  List<Device> devices = [];
  List<MusicTrack> music = [];
  List<LilyHome> homes = [];
  List<LilyRoom> rooms = [];

  bool get authenticated => api.token != null;

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
    try {
      await api.restoreSession();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
      } else {
        error = e.toString();
      }
    }

    if (api.token != null) {
      _restoreCache(prefs.getString('session_cache'));
      try {
        profile = await api.me();
        await refresh();
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) {
          await logout();
        } else {
          offline = true;
          error = e.toString();
        }
      }
    }

    if (!authenticated) await widgets.clear();
    initialized = true;
    notifyListeners();
  }

  Future<void> _storeToken(String token) async {
    api.token = token;
    final prefs = await SharedPreferences.getInstance();
    // New credentials are persisted by ApiService in platform secure storage.
    await prefs.remove('access_token');
  }

  Future<void> login(String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final token = await api.loginMobile(email, password);
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
      final token =
          await api.registerMobile(email, password, firstName, lastName);
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
    await widgets.clear();
    await api.logoutSession();
    api.token = null;
    profile = null;
    devices = [];
    music = [];
    homes = [];
    rooms = [];
    offline = false;
    await _clearCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('access_token')) {
      throw StateError('Could not clear the saved session.');
    }
  }

  Future<void> refresh() async {
    if (!authenticated) return;
    final revision = _sessionRevision;
    try {
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
      await _cacheSession();
      await widgets.publish(devices);
      if (revision != _sessionRevision) return;
      notifyListeners();
    } catch (e) {
      if (revision != _sessionRevision) return;
      if (e is ApiException && e.statusCode == 401) {
        await logout();
      } else {
        offline = true;
        devices = devices
            .map((d) => Device.fromJson({
                  ...d.toJson(),
                  'online': false,
                  'status':
                      d.status == 'RESET_PENDING' ? 'RESET_PENDING' : 'OFFLINE'
                }))
            .toList();
        notifyListeners();
      }
      rethrow;
    }
  }
}
