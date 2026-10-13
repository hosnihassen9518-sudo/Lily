import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import 'api_service.dart';

abstract interface class WidgetPlatform {
  Future<bool> supported();
  Future<void> configure(Map<String, dynamic> value);
  Future<void> update(Map<String, dynamic> snapshot);
  Future<void> clear();
}

class NativeWidgetPlatform implements WidgetPlatform {
  static const channel = MethodChannel('lily/widgets');
  @override
  Future<bool> supported() async {
    try {
      return await channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> configure(Map<String, dynamic> value) =>
      channel.invokeMethod('configure', value);
  @override
  Future<void> update(Map<String, dynamic> value) =>
      channel.invokeMethod('update', value);
  @override
  Future<void> clear() async {
    try {
      await channel.invokeMethod('clear');
    } on MissingPluginException {/* Host/web has no native widgets. */}
  }
}

class WidgetSync {
  WidgetSync(this.api, {WidgetPlatform? platform})
      : platform = platform ?? NativeWidgetPlatform();
  final ApiService api;
  final WidgetPlatform platform;
  int _revision = 0;
  String? _configuredFor;
  String status = 'Open Lily and sign in before adding a widget.';
  Future<void> _tail = Future<void>.value();
  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> clear() {
    _revision++;
    _configuredFor = null;
    status = 'Sign in to Lily to use widgets.';
    return _serialize(() async {
      try {
        await platform.clear();
      } catch (_) {
        // Parent-session revocation must proceed even if native storage fails.
      }
    });
  }

  Map<String, dynamic> snapshot(List<Device> devices) => {
        'devices': devices
            .map((d) => {
                  'id': d.id,
                  'generation': d.generation,
                  'name': d.displayName,
                  'serial_number': d.serial,
                  'status': d.status,
                  'online': d.online,
                  'enabled': d.supportsLight
                      ? d.lightEnabled
                      : (d.genericState['enabled'] is bool
                          ? d.genericState['enabled']
                          : null),
                  'supports_light': d.supportsLight,
                  'capabilities': d.capabilities,
                  'supports_audio': d.supportsAudio,
                  'supports_brightness': d.hasCapability('brightness'),
                  'supports_rgb': d.hasCapability('rgb'),
                  'supports_volume': d.hasCapability('volume'),
                  'can_control': d.online &&
                      !['RESET_PENDING', 'DISABLED', 'INVENTORY']
                          .contains(d.status) &&
                      (d.supportsLight || d.hasCapability('power')),
                })
            .toList(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
  Future<bool> publish(List<Device> devices, {bool force = false}) async {
    final revision = _revision,
        url = api.baseUrl,
        identity = api.sessionIdentity;
    bool current() =>
        revision == _revision &&
        url == api.baseUrl &&
        identity == api.sessionIdentity &&
        api.token != null;
    if (!current() || identity == null) return false;
    try {
      if (!await platform.supported()) {
        status = 'Home-screen widgets are not available on this device.';
        return false;
      }
      if (!current()) return false;
      final context = '$url|$identity';
      Map<String, dynamic>? config;
      if (force || _configuredFor != context) {
        final prefs = await SharedPreferences.getInstance();
        if (!current()) return false;
        var installation = prefs.getString('widget_installation_id');
        if (installation == null) {
          installation = List.generate(
              16,
              (_) => Random.secure()
                  .nextInt(256)
                  .toRadixString(16)
                  .padLeft(2, '0')).join();
          await prefs.setString('widget_installation_id', installation);
        }
        if (!current()) return false;
        final issued = await api.createWidgetSession(installation);
        if (!current()) return false;
        if (issued['token'] is! String || issued['expires_at'] is! String)
          throw const FormatException('Invalid widget setup response');
        config = {
          'backend_url': url,
          'token': issued['token'],
          'expires_at': issued['expires_at'],
          'snapshot': snapshot(devices)
        };
      }
      return await _serialize(() async {
        if (!current()) return false;
        if (config != null)
          await platform.configure(config);
        else
          await platform.update(snapshot(devices));
        if (!current()) return false;
        _configuredFor = context;
        status = 'Widgets are ready. Add Lily from your phone’s widget picker.';
        return true;
      });
    } catch (_) {
      if (current())
        status =
            'Could not update widgets. Check the connection and try again.';
      return false;
    }
  }
}
