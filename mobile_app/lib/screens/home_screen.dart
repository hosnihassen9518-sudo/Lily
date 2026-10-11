import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../widgets/device_card.dart';
import '../widgets/backend_settings_button.dart';
import 'home_management_screen.dart';
import 'music_screen.dart';
import 'pair_device_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? timer;
  int index = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => context.read<AppState>().refresh(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Widget _deviceGrid(BuildContext context, List<Device> devices) {
    if (devices.isEmpty) return const SizedBox.shrink();
    if (!kIsWeb) {
      return Column(
        children: devices
            .map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DeviceCard(device: d),
                ))
            .toList(),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1150 ? 3 : width > 720 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.75,
          children: devices.map((d) => DeviceCard(device: d)).toList(),
        );
      },
    );
  }

  Widget _roomSection(BuildContext context, String title, List<Device> devices) {
    if (devices.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined, size: 20),
              const SizedBox(width: 7),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('${devices.length}', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 10),
          _deviceGrid(context, devices),
        ],
      ),
    );
  }

  Widget _devicesPage(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.devices.isEmpty) {
      return RefreshIndicator(
        onRefresh: state.refresh,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _header(context),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    const Icon(Icons.devices_other, size: 48),
                    const SizedBox(height: 12),
                    const Text('No Lily device yet', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      kIsWeb
                          ? 'Use the Lily mobile app to add and provision a device.'
                          : 'Add your first Lily device and connect it to your home Wi-Fi.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final sections = <Widget>[];
    for (final home in state.homes) {
      final homeDevices = state.devices.where((d) => d.homeId == home.id).toList();
      if (homeDevices.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(home.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
      );
      final rooms = state.rooms.where((r) => r.homeId == home.id).toList();
      for (final room in rooms) {
        sections.add(_roomSection(context, room.name, homeDevices.where((d) => d.roomId == room.id).toList()));
      }
      sections.add(_roomSection(context, 'No room', homeDevices.where((d) => d.roomId == null).toList()));
    }
    final unassigned = state.devices.where((d) => d.homeId == null).toList();
    if (unassigned.isNotEmpty) sections.add(_roomSection(context, 'Unassigned devices', unassigned));

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [_header(context), const SizedBox(height: 22), ...sections],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My devices', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Devices are grouped by home and room.', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeManagementScreen())),
          icon: const Icon(Icons.home_work_outlined),
          label: const Text('Homes & rooms'),
        ),
        if (!kIsWeb) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairDeviceScreen()))
                .then((_) => context.read<AppState>().refresh()),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ],
    );
  }

  Widget _accountPage(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(state.profile?['email']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: state.logout, icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _devicesPage(context),
      const HomeManagementScreen(),
      const MusicScreen(),
      _accountPage(context),
    ];

    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lily'), actions: const [BackendSettingsButton()]),
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width > 1050,
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CircleAvatar(child: Text('L', style: TextStyle(fontWeight: FontWeight.w900))),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: Text('My devices')),
                NavigationRailDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work), label: Text('Homes & rooms')),
                NavigationRailDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: Text('Music')),
                NavigationRailDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('Account')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[index]),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lily'), actions: const [BackendSettingsButton()]),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}
