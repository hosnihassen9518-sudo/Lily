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

  Future<void> load() async {
    setState(() => loading = true);
    try {
      schedules = await context.read<AppState>().api.getSchedules(widget.device.id);
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
    final name = TextEditingController(text: 'Evening');
    TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
    final selectedDays = <int>{0, 1, 2, 3, 4, 5, 6};
    bool lightOn = true;
    bool audioPlay = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New schedule'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      return FilterChip(
                        label: Text(labels[day]),
                        selected: selectedDays.contains(day),
                        onSelected: (selected) {
                          setDialogState(() {
                            selected ? selectedDays.add(day) : selectedDays.remove(day);
                          });
                        },
                      );
                    }),
                  ),
                  SwitchListTile(
                    value: lightOn,
                    onChanged: (v) => setDialogState(() => lightOn = v),
                    title: const Text('Turn light on'),
                  ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    await context.read<AppState>().api.createSchedule(
          deviceId: widget.device.id,
          name: name.text.trim().isEmpty ? 'Schedule' : name.text.trim(),
          time: '$hh:$mm:00',
          days: selectedDays.toList(),
          action: {
            'light': {'enabled': lightOn},
            'audio': audioPlay ? 'play' : 'stop',
          },
        );

    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedules'),
        actions: [
          IconButton(onPressed: addSchedule, icon: const Icon(Icons.add)),
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
        onPressed: addSchedule,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
    );
  }
}
