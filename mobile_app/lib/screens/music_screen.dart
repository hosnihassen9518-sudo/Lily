import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/music_track.dart';
import '../state/app_state.dart';

class MusicScreen extends StatefulWidget {
  final int? deviceId;
  final Future<PlatformFile?> Function()? pickAudio;
  const MusicScreen({super.key, this.deviceId, this.pickAudio});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  bool busy = false;
  String? status;
  Future<void> choosePhoneFile() async {
    final state = context.read<AppState>();
    final backend = state.api.baseUrl, session = state.api.sessionIdentity;
    bool current() =>
        mounted &&
        state.api.baseUrl == backend &&
        state.api.sessionIdentity == session;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final PlatformFile? file;
      if (widget.pickAudio != null) {
        file = await widget.pickAudio!();
      } else {
        final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['mp3'],
            withData: false,
            withReadStream: true,
            allowMultiple: false);
        file = result?.files.single;
      }
      if (!current() || file == null) return;
      if (file.size > 20 * 1024 * 1024) {
        throw Exception('Choose an MP3 of 20 MB or less.');
      }
      var bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in file.readStream!) {
          if (!current()) return;
          if (buffer.length + chunk.length > 20 * 1024 * 1024) {
            throw Exception('Choose an MP3 of 20 MB or less.');
          }
          buffer.add(chunk);
        }
        bytes = buffer.takeBytes();
      }
      if (!current()) return;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('The selected MP3 could not be read.');
      }
      final filename = file.name;
      setState(() =>
          status = 'Uploading $filename privately to your Lily server...');
      final track =
          await state.api.uploadPrivateMusic(filename: filename, bytes: bytes);
      if (!current()) return;
      // An upload is confirmed independently of subsequent device availability.
      state.music = [
        ...state.music.where((item) => item.id != track.id),
        track
      ];
      setState(() => status =
          '${track.title} saved in My files. Choose Play to send it to Lily.');
    } catch (error) {
      if (current()) {
        setState(
            () => status = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> installTrack(MusicTrack track, {String mode = 'auto'}) async {
    final state = context.read<AppState>();
    final backendUrl = state.api.baseUrl, session = state.api.sessionIdentity;
    bool isCurrentSession() =>
        mounted &&
        state.api.baseUrl == backendUrl &&
        state.api.sessionIdentity == session;

    final audioDevices = state.devices
        .where((d) =>
            d.supportsAudio &&
            d.online &&
            (widget.deviceId == null || d.id == widget.deviceId))
        .toList();
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

    final hasAudioDevice = state.devices.any((d) =>
        d.supportsAudio &&
        (widget.deviceId == null || d.id == widget.deviceId));
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
          FilledButton.icon(
              onPressed: busy ? null : choosePhoneFile,
              icon: const Icon(Icons.audio_file),
              label: const Text('Choose MP3 from phone')),
          const SizedBox(height: 8),
          const Text(
              'Selected files are uploaded privately to your Lily server. MP3, up to 20 MB.'),
          const SizedBox(height: 18),
          Text('My files', style: Theme.of(context).textTheme.titleMedium),
          if (!state.music.any((track) => track.isPrivate))
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No private files uploaded yet.')),
          ...state.music
              .where((track) => track.isPrivate)
              .map((track) => trackCard(track, hasAudioDevice)),
          const SizedBox(height: 18),
          Text('Server catalog',
              style: Theme.of(context).textTheme.titleMedium),
          if (!state.music.any((track) => !track.isPrivate))
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('No music in the server catalog yet.'),
                          SizedBox(height: 8),
                          Text(
                              'Add MP3 tracks in the admin portal Music section, then refresh this page.'),
                        ]))),
          ...state.music
              .where((track) => !track.isPrivate)
              .map((track) => trackCard(track, hasAudioDevice)),
        ],
      ),
    );
  }

  Widget trackCard(MusicTrack track, bool hasAudioDevice) => Card(
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
              PopupMenuItem(value: 'stream', child: Text('Stream over Wi-Fi')),
            ],
            child:
                const Padding(padding: EdgeInsets.all(12), child: Text('Play')),
          ),
        ),
      );
}
