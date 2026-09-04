import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/music_track.dart';
import '../services/api_service.dart';

class AppState extends ChangeNotifier {
  final api = ApiService();

  bool initialized = false;
  bool busy = false;
  String? error;
  Map<String, dynamic>? profile;
  List<Device> devices = [];
  List<MusicTrack> music = [];

  bool get authenticated => api.token != null;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString('access_token');

    if (api.token != null) {
      try {
        profile = await api.me();
        await refresh();
      } catch (_) {
        await logout();
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
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    api.token = null;
    profile = null;
    devices = [];
    music = [];
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!authenticated) return;
    devices = await api.getDevices();
    music = await api.getMusic();
    notifyListeners();
  }
}
