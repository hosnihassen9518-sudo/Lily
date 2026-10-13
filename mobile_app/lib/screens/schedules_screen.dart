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
    try {
      schedules =
          await context.read<AppState>().api.getSchedules(widget.device.id);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> addSchedule() async {
    if (!canSchedule(currentDevice(context.read<AppState>()))) return;
    final name = TextEditingController(text: 'Evening');
    TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
    final selectedDays = <int>{0, 1, 2, 3, 4, 5, 6};
    bool lightOn = true;
    bool audioPlay = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Consumer<AppState>(
        builder: (context, state, child) => StatefulBuilder(
          builder: (context, setDialogState) {
            final device = currentDevice(state);
            return AlertDialog(
              title: const Text('New schedule'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (device == null) const Text('Device not found'),
                      TextField(
                        controller: name,
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
                        SwitchListTile(
                          value: lightOn,
                          onChanged: (v) => setDialogState(() => lightOn = v),
                          title: const Text('Turn light on'),
                        ),
                      if (device?.supportsAudio == true)
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
                  onPressed: canSchedule(device)
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

    if (ok != true || !mounted) return;
    final device = currentDevice(context.read<AppState>());
    if (!canSchedule(device)) return;

    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    await context.read<AppState>().api.createSchedule(
      deviceId: widget.device.id,
      name: name.text.trim().isEmpty ? 'Schedule' : name.text.trim(),
      time: '$hh:$mm:00',
      days: selectedDays.toList(),
      action: {
        if (device?.supportsLight == true) 'light': {'enabled': lightOn},
        if (device?.supportsAudio == true) 'audio': audioPlay ? 'play' : 'stop',
      },
    );

    if (mounted) await load();
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
              onPressed: canSchedule(device) ? addSchedule : null,
              icon: const Icon(Icons.add)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : schedules.isEmpty
              ? const Center(child: Text('No schedules yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: schedules.length,
                  itemBuilder: (context, index) {
                    final schedule = schedules[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text(schedule['name']?.toString() ?? 'Schedule'),
                        subtitle: Text(
                          '${schedule['time_of_day']} • ${schedule['days_of_week']}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await context
                                .read<AppState>()
                                .api
                                .deleteSchedule(schedule['id'] as int);
                            await load();
                          },
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canSchedule(device) ? addSchedule : null,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
    );
  }
}
