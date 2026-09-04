import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool registerMode = false;
  final email = TextEditingController(text: '');
  final password = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();

  Future<void> submit() async {
    try {
      final state = context.read<AppState>();
      if (registerMode) {
        await state.register(
          email.text.trim(),
          password.text,
          firstName.text.trim(),
          lastName.text.trim(),
        );
      } else {
        await state.login(email.text.trim(), password.text);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.all(28),
              shrinkWrap: true,
              children: [
                const CircleAvatar(
                  radius: 34,
                  child: Text(
                    'L',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  registerMode ? 'Create your Lily account' : 'Welcome to Lily',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  registerMode
                      ? 'Create an account, then add your device in a few steps.'
                      : 'Control lights, audio, and schedules from one place.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 30),
                if (registerMode) ...[
                  TextField(
                    controller: firstName,
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lastName,
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: state.busy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      state.busy
                          ? 'Please wait...'
                          : registerMode
                              ? 'Create account'
                              : 'Sign in',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => registerMode = !registerMode),
                  child: Text(
                    registerMode
                        ? 'Already have an account? Sign in'
                        : 'New to Lily? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
