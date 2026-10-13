import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/services/widget_sync.dart';
import 'package:lily_mobile/models/device.dart';

class DelayedWidgetPlatform implements WidgetPlatform {
  final entered = Completer<void>(), release = Completer<void>();
  Map<String, dynamic>? saved;
  bool delay = false;
  bool failClear = false;
  @override
  Future<bool> supported() async => true;
  @override
  Future<void> configure(Map<String, dynamic> value) async {
    if (delay) {
      entered.complete();
      await release.future;
    }
    saved = value;
  }

  @override
  Future<void> update(Map<String, dynamic> value) async {
    saved = {...?saved, 'snapshot': value};
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError("Native storage unavailable");
    saved = null;
  }
}

ApiService api() => ApiService(
    client: MockClient((r) async => http.Response(
        jsonEncode({
          'token': 'restricted-widget-token',
          'expires_at': DateTime.now()
              .add(const Duration(days: 90))
              .toUtc()
              .toIso8601String()
        }),
        200)))
  ..token =
      'h.${base64Url.encode(utf8.encode(jsonEncode({'sid': 'parent-one'})))}.s';
void main() {
  test('Widget projection requires explicit model features', () {
    final sync = WidgetSync(api(), platform: DelayedWidgetPlatform());
    for (final caps in <List<String>>[
      [],
      ['power'],
      ['light'],
      ['light', 'brightness', 'rgb', 'audio', 'volume']
    ]) {
      final d = Device.fromJson({
        'id': 1,
        'serial_number': 'TEST',
        'status': 'ONLINE',
        'online': true,
        'smart_home': {'capabilities': caps}
      });
      final row = (sync.snapshot([d])['devices'] as List).single as Map;
      expect(
          row['can_control'], caps.contains('light') || caps.contains('power'));
      expect(row['supports_audio'], caps.contains('audio'));
      expect(row['supports_brightness'], caps.contains('brightness'));
      expect(row['supports_rgb'], caps.contains('rgb'));
      expect(row['supports_volume'], caps.contains('volume'));
    }
  });

  test("Native widget clear failure does not block app logout", () async {
    final platform = DelayedWidgetPlatform()..failClear = true;
    final sync = WidgetSync(api(), platform: platform);
    await sync.clear();
    expect(sync.status, contains("Sign in"));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'Logout while native configure is pending cannot restore widget credentials',
      () async {
    final platform = DelayedWidgetPlatform()..delay = true;
    final sync = WidgetSync(api(), platform: platform);
    final writing = sync.publish([]);
    await platform.entered.future;
    final clearing = sync.clear();
    platform.release.complete();
    await writing;
    await clearing;
    expect(platform.saved, isNull);
  });
  test(
      'Reset pending snapshots keep power buttons disabled and omit account credentials',
      () async {
    final platform = DelayedWidgetPlatform();
    final sync = WidgetSync(api(), platform: platform);
    final device = Device.fromJson({
      'id': 1,
      'serial_number': 'CLOUD',
      'online': true,
      'status': 'RESET_PENDING',
      'smart_home': {
        'capabilities': ['power', 'light']
      }
    });
    expect(await sync.publish([device]), isTrue);
    final snapshot = platform.saved!['snapshot'] as Map;
    final row = (snapshot['devices'] as List).single as Map;
    expect(row['can_control'], isFalse);
    expect(row['status'], 'RESET_PENDING');
    expect(jsonEncode(snapshot), isNot(contains('restricted-widget-token')));
    expect(jsonEncode(snapshot), isNot(contains('refresh_token')));
  });
}
