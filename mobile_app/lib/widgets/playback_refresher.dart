import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

/// Keeps visible playback views current without reloading music and home catalogs.
class PlaybackRefresher extends StatefulWidget {
  final Widget child;
  const PlaybackRefresher({super.key, required this.child});
  @override
  State<PlaybackRefresher> createState() => _PlaybackRefresherState();
}

class _PlaybackRefresherState extends State<PlaybackRefresher>
    with WidgetsBindingObserver {
  Timer? timer;
  bool foreground = true;
  bool refreshing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
  }

  Future<void> refresh() async {
    if (!mounted ||
        !foreground ||
        refreshing ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final state = context.read<AppState>();
    if (!state.authenticated) return;
    refreshing = true;
    try {
      await state.refreshDevices();
    } catch (_) {/* Keep the last confirmed state. */} finally {
      refreshing = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
