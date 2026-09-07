import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/home.dart';
import '../state/app_state.dart';

class HomeManagementScreen extends StatelessWidget {
  const HomeManagementScreen({super.key});

  Future<String?> _nameDialog(BuildContext context, String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
      if (context.mounted) await context.read<AppState>().refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _roomTile(BuildContext context, LilyRoom room) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.meeting_room_outlined)),
      title: Text(room.name),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            final name = await _nameDialog(context, 'Rename room', initial: room.name);
            if (name != null && context.mounted) {
              await _run(context, () => context.read<AppState>().api.renameRoom(room.id, name));
            }
          } else if (value == 'delete') {
            await _run(context, () => context.read<AppState>().api.deleteRoom(room.id));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Homes & rooms')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await _nameDialog(context, 'New home');
          if (name != null && context.mounted) {
            await _run(context, () => context.read<AppState>().api.createHome(name));
          }
        },
        icon: const Icon(Icons.add_home),
        label: const Text('Add home'),
      ),
      body: state.homes.isEmpty
          ? const Center(child: Text('No home configured.'))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: state.homes.map((home) {
                final homeRooms = state.rooms.where((r) => r.homeId == home.id).toList();
                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
                    title: Text(home.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${homeRooms.length} room${homeRooms.length == 1 ? '' : 's'}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'room') {
                          final name = await _nameDialog(context, 'Add room to ${home.name}');
                          if (name != null && context.mounted) {
                            await _run(context, () => context.read<AppState>().api.createRoom(home.id, name));
                          }
                        } else if (value == 'rename') {
                          final name = await _nameDialog(context, 'Rename home', initial: home.name);
                          if (name != null && context.mounted) {
                            await _run(context, () => context.read<AppState>().api.renameHome(home.id, name));
                          }
                        } else if (value == 'delete') {
                          await _run(context, () => context.read<AppState>().api.deleteHome(home.id));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'room', child: Text('Add room')),
                        PopupMenuItem(value: 'rename', child: Text('Rename home')),
                        PopupMenuItem(value: 'delete', child: Text('Delete home')),
                      ],
                    ),
                    children: [
                      if (homeRooms.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 4, 20, 18),
                          child: Align(alignment: Alignment.centerLeft, child: Text('No rooms yet.')),
                        )
                      else
                        ...homeRooms.map((r) => _roomTile(context, r)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
