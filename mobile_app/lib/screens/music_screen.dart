import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/music_track.dart';
import '../services/provision_service.dart';
import '../state/app_state.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  bool busy = false;
  String? status;

  Future<void> installTrack(MusicTrack track) async {
    final state = context.read<AppState>();

    if (state.devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a Lily device first.')),
      );
      return;
    }

    setState(() {
      busy = true;
      status = 'Downloading ${track.title}...';
    });

    try {
      final bytes = await state.api.downloadMusic(track.id);

      setState(() {
        status =
            'Downloaded. Connect your phone to the Lily device setup Wi-Fi, then continue.';
      });

      if (!mounted) return;

      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transfer to Lily'),
          content: const Text(
            'For V0.4 the MP3 is transferred directly over the device local Wi-Fi. '
            'Connect to the Lily setup network and press Transfer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Transfer'),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      setState(() => status = 'Uploading to device...');
      await ProvisionService().uploadMp3(
        bytes: bytes,
        checksum: track.checksum,
      );

      setState(() => status = '${track.title} installed successfully.');
    } catch (e) {
      setState(() => status = e.toString());
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Music',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose one sound to store on your Lily device.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (status != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(status!),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...state.music.map(
            (track) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.music_note)),
                title: Text(
                  track.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  track.description ?? track.filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonal(
                  onPressed: busy ? null : () => installTrack(track),
                  child: const Text('Install'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
