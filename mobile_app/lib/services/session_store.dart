import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionStore {
  Future<Map<String, dynamic>?> read(String backendUrl);
  Future<void> write(String backendUrl, Map<String, dynamic> session);
  Future<void> clear(String backendUrl);
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  String key(String url) =>
      'lily.session.${base64Url.encode(utf8.encode(url))}';
  @override
  Future<Map<String, dynamic>?> read(String backendUrl) async {
    String? raw;
    try {
      raw = await storage.read(key: key(backendUrl));
    } on MissingPluginException {
      return null;
    }
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on FormatException {
      await clear(backendUrl);
      return null;
    } on TypeError {
      await clear(backendUrl);
      return null;
    }
  }

  @override
  Future<void> write(String url, Map<String, dynamic> session) =>
      storage.write(key: key(url), value: jsonEncode(session));
  @override
  Future<void> clear(String url) async {
    try {
      await storage.delete(key: key(url));
    } on MissingPluginException {/* No secure store in host widget tests. */}
  }
}
