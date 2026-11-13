import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/music_track.dart';
import '../state/app_state.dart';
import '../theme/lily_theme.dart';
import '../widgets/playback_refresher.dart';

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
  String query = '';
  bool showPrivate = false;
  bool streamOnly = false;
  bool statusIsError = false;
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
      statusIsError = false;
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
      setState(() {
        showPrivate = true;
        query = '';
        status =
            '${track.title} saved in My files. Choose Play to send it to Lily.';
      });
    } catch (error) {
      if (current()) {
        setState(() {
          statusIsError = true;
          status = error.toString().replaceFirst('Exception: ', '');
        });
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
      statusIsError = false;
      status = 'Starting ${track.title}...';
    });

    try {
      await state.api.selectCatalogAudio(targetDevice.id, track.id, mode: mode);
      if (!isCurrentSession()) return;
      await state.refreshDevices();
      if (!isCurrentSession()) return;
      setState(() => status =
          'Playback requested on ${targetDevice.displayName}. Check the device for download or playback status.');
    } catch (e) {
      if (isCurrentSession()) {
        setState(() {
          statusIsError = true;
          status = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = LilyTheme.forAppearance(state.appearance);
    final scheme = theme.colorScheme;
    final devices = state.devices
        .where((d) =>
            d.supportsAudio &&
            (widget.deviceId == null || d.id == widget.deviceId))
        .toList();
    final hasAudioDevice = devices.isNotEmpty;
    final online = devices.any((d) => d.online);
    final selectedDevice = devices.length == 1 ? devices.first : null;
    final tracks = state.music
        .where((track) =>
            track.isPrivate == showPrivate &&
            ('${track.title} ${track.filename}')
                .toLowerCase()
                .contains(query.toLowerCase()))
        .toList();
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: widget.deviceId == null
            ? null
            : AppBar(title: const Text('Choose audio')),
        body: PlaybackRefresher(
          child: RefreshIndicator(
            onRefresh: state.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                if (widget.deviceId == null) ...[
                  Text('Music',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                ],
                Card(
                    child: ListTile(
                  leading: Icon(online ? Icons.speaker : Icons.volume_off),
                  title: Text(selectedDevice?.displayName ??
                      (hasAudioDevice
                          ? 'Choose Lily when you press Play'
                          : 'No audio device')),
                  subtitle: Text(online
                      ? 'Ready to play'
                      : hasAudioDevice
                          ? 'Lily is offline. Connect it to play audio.'
                          : 'Add an audio-capable Lily device to install music.'),
                )),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                      labelText: 'Search audio',
                      hintText: 'Search by name',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('My files')),
                    ButtonSegment(value: false, label: Text('Server catalog'))
                  ],
                  selected: {showPrivate},
                  onSelectionChanged: (value) =>
                      setState(() => showPrivate = value.single),
                ),
                const SizedBox(height: 12),
                if (showPrivate || state.music.isEmpty)
                  OutlinedButton.icon(
                      onPressed: busy ? null : choosePhoneFile,
                      icon: const Icon(Icons.add),
                      label: const Text('Choose MP3 from phone')),
                if (status != null) ...[
                  const SizedBox(height: 12),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (busy)
                                  const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                else
                                  Icon(
                                      statusIsError
                                          ? Icons.error_outline
                                          : Icons.check_circle_outline,
                                      color: statusIsError
                                          ? scheme.error
                                          : scheme.primary),
                                const SizedBox(width: 10),
                                Expanded(child: Text(status!)),
                              ]))),
                ],
                if (selectedDevice?.audioDownloading == true) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const Text('Saving audio to Lily...'),
                ],
                if (selectedDevice?.audioError?.isNotEmpty == true)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(selectedDevice!.audioError!,
                          style: TextStyle(color: scheme.error))),
                const SizedBox(height: 12),
                if (tracks.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 24, horizontal: 8),
                      child: Column(children: [
                        Icon(
                            query.isNotEmpty
                                ? Icons.search_off
                                : Icons.library_music_outlined,
                            size: 36,
                            color: scheme.primary),
                        const SizedBox(height: 12),
                        Text(query.isNotEmpty
                            ? 'No matching audio.'
                            : showPrivate
                                ? 'No private files uploaded yet.'
                                : 'No music in the server catalog yet.'),
                        const SizedBox(height: 8),
                        if (query.isEmpty)
                          Text(
                              showPrivate
                                  ? 'Add an MP3 from your phone. Only your account can see it.'
                                  : 'Add tracks in the admin portal, then pull down to refresh.',
                              textAlign: TextAlign.center),
                      ])),
                ...tracks.map((track) => trackCard(track, online, scheme)),
                const SizedBox(height: 16),
                Card(
                    child: ExpansionTile(
                  title: const Text('Playback options'),
                  subtitle: Text(streamOnly
                      ? 'Always stream over Wi-Fi'
                      : 'Save when space allows'),
                  children: [
                    SwitchListTile(
                        title: const Text('Always stream over Wi-Fi'),
                        subtitle: const Text(
                            'Otherwise, Lily saves the track when it fits.'),
                        value: streamOnly,
                        onChanged: (value) =>
                            setState(() => streamOnly = value))
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget trackCard(MusicTrack track, bool online, ColorScheme scheme) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: const Icon(Icons.music_note)),
          title: Text(track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${(track.filesize / (1024 * 1024)).toStringAsFixed(1)} MB · ${track.isPrivate ? 'Private file' : 'Catalog'}'),
          trailing: FilledButton(
              onPressed: busy || !online
                  ? null
                  : () =>
                      installTrack(track, mode: streamOnly ? 'stream' : 'auto'),
              child: const Text('Play')),
        ),
      );
}
