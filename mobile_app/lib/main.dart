import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme/lily_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = AppState();
  await state.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const LilyApp(),
    ),
  );
}

class LilyApp extends StatelessWidget {
  const LilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return MaterialApp(
      title: 'Lily',
      debugShowCheckedModeBanner: false,
      theme: LilyTheme.light,
      home: state.authenticated ? const HomeScreen() : const AuthScreen(),
    );
  }
}
