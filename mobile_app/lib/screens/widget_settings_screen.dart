import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/lily_logo.dart';

class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({super.key});
  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  bool updating = false;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
        appBar: AppBar(title: const LilyLogo()),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Home-screen widgets',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/branding/lily_cloud.png',
                  height: 140, fit: BoxFit.cover)),
          const SizedBox(height: 16),
          const Text(
              'See your devices and switch them on or off without opening Lily. Offline devices and devices waiting for reset cannot be controlled.'),
          const SizedBox(height: 16),
          const Text(
              'Android: touch and hold an empty area on your home screen, choose Widgets, then Lily.\n\niPhone: touch and hold the home screen, choose Add Widget, then Lily. Control widgets require iOS 17 or later.'),
          const SizedBox(height: 16),
          Text(state.widgets.status),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: updating
                  ? null
                  : () async {
                      setState(() => updating = true);
                      await state.widgets.publish(state.devices, force: true);
                      if (mounted) setState(() => updating = false);
                    },
              icon: const Icon(Icons.widgets_outlined),
              label: Text(updating ? 'Updating…' : 'Enable / refresh widgets')),
          const SizedBox(height: 12),
          const Text(
              'Widgets use your current account and stop working when you sign out or your session expires. Refresh times are managed by your phone.'),
        ]));
  }
}
