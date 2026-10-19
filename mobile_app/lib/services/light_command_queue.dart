import 'dart:async';
import 'package:flutter/foundation.dart';

/// Coalesces drag updates and keeps the final intent alive after navigation.
class LightCommandQueue {
  final Future<void> Function(Map<String, Object?>) send;
  void Function(Object) onError;
  final Duration minimumInterval;
  final Duration debounce;
  Timer? _timer;
  Map<String, Object?>? _inFlight;
  Map<String, Object?>? get latestIntent => _pending ?? _inFlight;

  // A new view reads authoritative state; old completed writes must not mask it.
  void reconcile() {
    if (!_sending && _pending == null) _lastSent = null;
  }

  Map<String, Object?>? _pending;
  Map<String, Object?>? _lastSent;
  DateTime? _lastSend;
  bool _sending = false;

  LightCommandQueue(
      {required this.send,
      required this.onError,
      this.minimumInterval = const Duration(milliseconds: 2200),
      this.debounce = const Duration(milliseconds: 220)});

  Future<void> enqueue(Map<String, Object?> values, {bool immediate = false}) {
    _pending = Map.unmodifiable(values);
    _timer?.cancel();
    _timer = null;
    if (immediate) return _drain();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_drain());
    });
    return Future.value();
  }

  Future<void> _drain() async {
    if (_sending) return;
    _sending = true;
    _timer?.cancel();
    _timer = null;
    try {
      while (_pending != null) {
        if (_lastSend != null) {
          final wait = minimumInterval - DateTime.now().difference(_lastSend!);
          if (wait > Duration.zero) await Future<void>.delayed(wait);
        }
        final values = _pending!;
        _pending = null;
        if (mapEquals(values, _lastSent)) continue;
        _lastSend = DateTime.now();
        _inFlight = values;
        try {
          await send(values);
          _lastSent = values;
        } catch (error) {
          _lastSent = null;
          onError(error);
        } finally {
          _inFlight = null;
        }
      }
    } finally {
      _sending = false;
    }
  }
}
