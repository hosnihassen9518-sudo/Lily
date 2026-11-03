import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/music_track.dart';
import '../state/app_state.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  bool busy = false;
  String? status;

  Future<void> installTrack(MusicTrack track, {String mode = 'auto'}) async {
    final state = context.read<AppState>();
    final backendUrl = state.api.baseUrl;
    bool isCurrentSession() => mounted && state.api.baseUrl == backendUrl;

    final audioDevices =
        state.devices.where((d) => d.supportsAudio && d.online).toList();
    if (audioDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Connect an audio-capable Lily device first.')),
      );
      return;
    }

    var targetDevice = audioDevices.first;
    if (audioDevices.length > 1) {
      final selected = await showDialog<int>(
        context: context,
        builder: (context) {
          int value = targetDevice.id;
          return StatefulBuilder(
            builder: (context, setLocalState) => AlertDialog(
              title: const Text('Choose device'),
              content: DropdownButtonFormField<int>(
                initialValue: value,
                items: audioDevices
                    .map((d) => DropdownMenuItem(
                        value: d.id, child: Text(d.displayName)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setLocalState(() => value = v);
                },
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, value),
                    child: const Text('Continue')),
              ],
            ),
          );
        },
      );
      if (!isCurrentSession() || selected == null) return;
      targetDevice = audioDevices.firstWhere((d) => d.id == selected);
    }

    setState(() {
      busy = true;
      status = 'Requesting ${track.title}...';
    });

    try {
      await state.api.selectCatalogAudio(targetDevice.id, track.id, mode: mode);
      if (!isCurrentSession()) return;
      await state.refresh();
      if (!isCurrentSession()) return;
      setState(() => status =
          'Playback requested on ${targetDevice.displayName}. Check the device for download or playback status.');
    } catch (e) {
      if (isCurrentSession()) setState(() => status = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final hasAudioDevice = state.devices.any((d) => d.supportsAudio);
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
            'Play over Wi-Fi. Auto stores one MP3 when space allows, otherwise streams.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (!hasAudioDevice)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child:
                    Text('Add an audio-capable Lily device to install music.')),
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
                trailing: PopupMenuButton<String>(
                  enabled: !busy && hasAudioDevice,
                  tooltip: 'Choose playback mode',
                  onSelected: (mode) => installTrack(track, mode: mode),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'auto', child: Text('Auto: store or stream')),
                    PopupMenuItem(
                        value: 'stream', child: Text('Stream over Wi-Fi')),
                  ],
                  child: const Padding(
                      padding: EdgeInsets.all(12), child: Text('Play')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
