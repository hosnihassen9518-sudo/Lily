import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/music_track.dart';
import '../models/home.dart';
import '../services/api_service.dart';
import '../models/backend_settings.dart';

class AppState extends ChangeNotifier {
  AppState({ApiService? api}) : api = api ?? ApiService() {
    this.api.onSessionInvalidated = () {
      _sessionRevision++;
      profile = null;
      devices = [];
      music = [];
      homes = [];
      rooms = [];
      notifyListeners();
    };
  }

  @override
  void dispose() {
    api.onSessionInvalidated = null;
    super.dispose();
  }

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
      try {
        profile = await api.me();
        await refresh();
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) {
          await logout();
        } else {
          error = e.toString();
        }
      }
    }

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
    await api.logoutSession();
    api.token = null;
    profile = null;
    devices = [];
    music = [];
    homes = [];
    rooms = [];
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
      notifyListeners();
    } catch (e) {
      if (revision != _sessionRevision) return;
      if (e is ApiException && e.statusCode == 401) await logout();
      rethrow;
    }
  }
}
