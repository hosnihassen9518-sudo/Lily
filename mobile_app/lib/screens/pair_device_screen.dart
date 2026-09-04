import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/provision_service.dart';
import '../state/app_state.dart';

class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final provision = ProvisionService();
  final apSsid = TextEditingController(text: 'LILY-');
  final wifiSsid = TextEditingController();
  final wifiPassword = TextEditingController();

  int step = 0;
  bool busy = false;
  String? serial;
  String message = '';

  Future<void> connectDevice() async {
    setState(() {
      busy = true;
      message = 'Connecting to the Lily setup network...';
    });
    try {
      final connected = await provision.connectToDeviceAp(apSsid.text.trim());
      if (!connected) throw Exception('Could not join the Lily Wi-Fi network.');
      final info = await provision.getDeviceInfo();
      serial = info['serial']?.toString();
      setState(() {
        step = 1;
        message = 'Connected to ${serial ?? 'device'}.';
      });
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> provisionHomeWifi() async {
    setState(() {
      busy = true;
      message = 'Sending Wi-Fi configuration...';
    });

    try {
      final pairingToken =
          await context.read<AppState>().api.createPairingToken();

      await provision.provisionWifi(
        wifiSsid: wifiSsid.text.trim(),
        wifiPassword: wifiPassword.text,
        pairingToken: pairingToken,
      );

      setState(() {
        step = 2;
        message =
            'Configuration sent. The device is joining your home Wi-Fi and registering to your account.';
      });

      await Future.delayed(const Duration(seconds: 8));
      await context.read<AppState>().refresh();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a Lily device')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const _StepHeader(
                number: 1,
                title: 'Connect to the device',
                text:
                    'Turn the Lily device on. Its setup network starts with LILY-.',
              ),
              TextField(
                controller: apSsid,
                decoration: const InputDecoration(
                  labelText: 'Device setup Wi-Fi name',
                  hintText: 'LILY-A1B2',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : connectDevice,
                child: const Text('Connect to device'),
              ),
              const Divider(height: 44),
              const _StepHeader(
                number: 2,
                title: 'Connect Lily to your home Wi-Fi',
                text:
                    'Enter your normal home Wi-Fi. A short-lived secure token will associate the physical device to your account.',
              ),
              TextField(
                controller: wifiSsid,
                decoration: const InputDecoration(labelText: 'Home Wi-Fi name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wifiPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Wi-Fi password'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || step < 1 ? null : provisionHomeWifi,
                child: const Text('Finish setup'),
              ),
              const SizedBox(height: 20),
              if (message.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(message),
                  ),
                ),
              if (step == 2)
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int number;
  final String title;
  final String text;

  const _StepHeader({
    required this.number,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, child: Text('$number')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
