import 'package:flutter/material.dart';
import '../screens/backend_settings_screen.dart';

class BackendSettingsButton extends StatelessWidget {
  const BackendSettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Backend settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const BackendSettingsScreen(),
        )),
      );
}
