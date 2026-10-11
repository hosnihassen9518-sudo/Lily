import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/backend_settings.dart';
import '../state/app_state.dart';

class BackendSettingsScreen extends StatefulWidget {
  const BackendSettingsScreen({super.key});

  @override
  State<BackendSettingsScreen> createState() => _BackendSettingsScreenState();
}

class _BackendSettingsScreenState extends State<BackendSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  late String _scheme;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppState>().backendSettings;
    _host = TextEditingController(text: settings.host);
    _port = TextEditingController(text: '${settings.port}');
    _scheme = settings.scheme;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context
          .read<AppState>()
          .saveBackendSettings(BackendSettings.validated(
            host: _host.text,
            port: _port.text,
            scheme: _scheme,
          ));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backend settings saved.')));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save settings. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Backend settings')),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('Enter the address of your Lily server.'),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _host,
                  decoration: const InputDecoration(
                      labelText: 'IP address or hostname',
                      hintText: '192.168.1.100'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (value) => BackendSettings.hostError(value ?? ''),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _port,
                  decoration: const InputDecoration(
                      labelText: 'Port', hintText: '6100'),
                  keyboardType: TextInputType.number,
                  validator: (value) => BackendSettings.portError(value ?? ''),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _scheme,
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  items: const [
                    DropdownMenuItem(value: 'http', child: Text('HTTP')),
                    DropdownMenuItem(value: 'https', child: Text('HTTPS')),
                  ],
                  onChanged: (value) => setState(() => _scheme = value!),
                ),
                const SizedBox(height: 16),
                Text(
                    'Server: $_scheme://${_host.text.trim()}:${_port.text.trim()}/api/v1'),
                const SizedBox(height: 12),
                const Text(
                    'Changing the server signs you out. These settings are saved on this device.'),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _saving || state.busy ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save')),
              ],
            )),
      )),
    );
  }
}
