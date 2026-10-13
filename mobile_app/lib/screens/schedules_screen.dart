import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';

class SchedulesScreen extends StatefulWidget {
  final Device device;
  const SchedulesScreen({super.key, required this.device});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  List<Map<String, dynamic>> schedules = [];
  bool loading = true;
  String? error;
  static const dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  Map<String, dynamic> normalizeAction(Map<String, dynamic> action) {
    final payload = Map<String, dynamic>.from(action['payload'] ?? {});
    switch (action['type']) {
      case 'light':
        return {'light': payload};
      case 'audio_play':
        return {'audio': 'play'};
      case 'audio_stop':
        return {'audio': 'stop'};
      case 'volume':
        return {'volume': payload['volume']};
      default:
        return action;
    }
  }

  String daysText(List days) {
    final sorted = days.cast<int>().toSet().toList()..sort();
    if (sorted.length == 7) return 'Every day';
    if (sorted.join(',') == '0,1,2,3,4') return 'Weekdays';
    if (sorted.join(',') == '5,6') return 'Weekends';
    return sorted
        .where((d) => d >= 0 && d < 7)
        .map((d) => dayNames[d])
        .join(', ');
  }

  String timeText(dynamic value) {
    final parts = value.toString().split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]))
        .format(context);
  }

  Future<void> change(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save schedule. Please try again.')));
      }
    }
  }

  Device? currentDevice(AppState state) {
    for (final device in state.devices) {
      if (device.id == widget.device.id) return device;
    }
    return null;
  }

  bool canSchedule(Device? device) =>
      device != null && (device.supportsLight || device.supportsAudio);

  Future<void> load() async {
    if (!mounted || currentDevice(context.read<AppState>()) == null) return;
    setState(() => loading = true);
    error = null;
    try {
      schedules =
          await context.read<AppState>().api.getSchedules(widget.device.id);
    } catch (e) {
      error = 'Could not load schedules. Pull to refresh.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> addSchedule([Map<String, dynamic>? existing]) async {
    if (!canSchedule(currentDevice(context.read<AppState>()))) return;
    String name = existing?['name'] ?? 'Evening';
    final parts = (existing?['time_of_day'] ?? '20:00').toString().split(':');
    TimeOfDay time =
        TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final selectedDays =
        ((existing?['days_of_week'] as List?) ?? [0, 1, 2, 3, 4, 5, 6])
            .cast<int>()
            .toSet();
    final originalAction =
        normalizeAction(Map<String, dynamic>.from(existing?['action'] ?? {}));
    bool includeLight = existing == null || originalAction.containsKey('light');
    bool includeAudio = existing == null || originalAction.containsKey('audio');
    bool lightOn = originalAction['light']?['enabled'] ?? true;
    bool audioPlay = originalAction['audio'] == 'play';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Consumer<AppState>(
        builder: (context, state, child) => StatefulBuilder(
          builder: (context, setDialogState) {
            final device = currentDevice(state);
            return AlertDialog(
              title: Text(existing == null ? 'New schedule' : 'Edit schedule'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (device == null) const Text('Device not found'),
                      TextFormField(
                        initialValue: name,
                        onChanged: (value) => name = value,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        title: const Text('Time'),
                        trailing: Text(time.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: time,
                          );
                          if (picked != null) {
                            setDialogState(() => time = picked);
                          }
                        },
                      ),
                      const Text('Repeat on'),
                      const Text('Paris time · adjusts for daylight saving',
                          style: TextStyle(fontSize: 12)),
                      Wrap(spacing: 6, children: [
                        for (final preset in [
                          'Every day',
                          'Weekdays',
                          'Weekends'
                        ])
                          ActionChip(
                              label: Text(preset),
                              onPressed: () => setDialogState(() {
                                    selectedDays.clear();
                                    selectedDays.addAll(preset == 'Every day'
                                        ? [0, 1, 2, 3, 4, 5, 6]
                                        : preset == 'Weekdays'
                                            ? [0, 1, 2, 3, 4]
                                            : [5, 6]);
                                  })),
                      ]),
                      Wrap(
                        spacing: 6,
                        children: List.generate(7, (day) {
                          const labels = [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun'
                          ];
                          return FilterChip(
                            label: Text(labels[day]),
                            selected: selectedDays.contains(day),
                            onSelected: (selected) {
                              setDialogState(() {
                                selected
                                    ? selectedDays.add(day)
                                    : selectedDays.remove(day);
                              });
                            },
                          );
                        }),
                      ),
                      if (device?.supportsLight == true)
                        CheckboxListTile(
                            value: includeLight,
                            onChanged: (v) =>
                                setDialogState(() => includeLight = v ?? false),
                            title: const Text('Change light')),
                      if (device?.supportsLight == true && includeLight)
                        SwitchListTile(
                          value: lightOn,
                          onChanged: (v) => setDialogState(() => lightOn = v),
                          title: const Text('Turn light on'),
                        ),
                      if (device?.supportsAudio == true)
                        CheckboxListTile(
                            value: includeAudio,
                            onChanged: (v) =>
                                setDialogState(() => includeAudio = v ?? false),
                            title: const Text('Change audio')),
                      if (device?.supportsAudio == true && includeAudio)
                        SwitchListTile(
                          value: audioPlay,
                          onChanged: (v) => setDialogState(() => audioPlay = v),
                          title: const Text('Play audio'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canSchedule(device) &&
                          selectedDays.isNotEmpty &&
                          ((includeLight && device?.supportsLight == true) ||
                              (includeAudio && device?.supportsAudio == true) ||
                              (device?.hasCapability('volume') == true &&
                                  originalAction.containsKey('volume')))
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (ok != true || !mounted) {
      return;
    }
    final device = currentDevice(context.read<AppState>());
    if (!canSchedule(device)) return;

    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    final action = <String, dynamic>{
      if (device?.supportsLight == true && includeLight)
        'light': {
          for (final entry
              in Map<String, dynamic>.from(originalAction['light'] ?? {})
                  .entries)
            if ((entry.key == 'brightness' &&
                    device?.hasCapability('brightness') == true) ||
                (['r', 'g', 'b'].contains(entry.key) &&
                    device?.hasCapability('rgb') == true))
              entry.key: entry.value,
          'enabled': lightOn
        },
      if (device?.supportsAudio == true && includeAudio)
        'audio': audioPlay ? 'play' : 'stop',
      if (device?.hasCapability('volume') == true &&
          originalAction.containsKey('volume'))
        'volume': originalAction['volume'],
    };
    final api = context.read<AppState>().api;
    final title = name.trim().isEmpty ? 'Schedule' : name.trim();
    await change(() => existing == null
        ? api.createSchedule(
            deviceId: widget.device.id,
            name: title,
            time: '$hh:$mm:00',
            days: selectedDays.toList()..sort(),
            action: action)
        : api.updateSchedule(existing['id'] as int, {
            'name': title,
            'time_of_day': '$hh:$mm:00',
            'days_of_week': selectedDays.toList()..sort(),
            'action': action,
            'enabled': existing['enabled'] ?? true
          }));
  }

  @override
  Widget build(BuildContext context) {
    final device = currentDevice(context.watch<AppState>());
    if (device == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Schedules')),
          body: const Center(child: Text('Device not found')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedules'),
        actions: [
          IconButton(
              onPressed: canSchedule(device) ? () => addSchedule() : null,
              icon: const Icon(Icons.add)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: TextButton(onPressed: load, child: Text(error!)))
              : schedules.isEmpty
                  ? const Center(child: Text('No schedules yet.'))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: schedules.length,
                        itemBuilder: (context, index) {
                          final schedule = schedules[index];
                          return Card(
                            child: ListTile(
                              onTap: canSchedule(device)
                                  ? () => addSchedule(schedule)
                                  : null,
                              leading: const Icon(Icons.schedule),
                              title: Text(
                                  schedule['name']?.toString() ?? 'Schedule'),
                              subtitle: Text(
                                '${timeText(schedule['time_of_day'])} · ${daysText(schedule['days_of_week'] as List)}\n${schedule['enabled'] == false ? 'Paused' : 'Active'} · Tap to edit',
                              ),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                        value: schedule['enabled'] != false,
                                        onChanged: canSchedule(device)
                                            ? (enabled) => change(() => context
                                                .read<AppState>()
                                                .api
                                                .updateSchedule(
                                                    schedule['id'] as int,
                                                    {...schedule}
                                                      ..remove('id')
                                                      ..['enabled'] = enabled))
                                            : null),
                                    IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Delete schedule',
                                        onPressed: () async {
                                          final confirmed = await showDialog<
                                                  bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                      title: const Text(
                                                          'Delete schedule?'),
                                                      content: Text(
                                                          'Remove ${schedule['name']}?'),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    false),
                                                            child: const Text(
                                                                'Cancel')),
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    true),
                                                            child: const Text(
                                                                'Delete'))
                                                      ]));
                                          if (confirmed == true && mounted) {
                                            await change(() => context
                                                .read<AppState>()
                                                .api
                                                .deleteSchedule(
                                                    schedule['id'] as int));
                                          }
                                        }),
                                  ]),
                            ),
                          );
                        },
                      )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canSchedule(device) ? () => addSchedule() : null,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
    );
  }
}
