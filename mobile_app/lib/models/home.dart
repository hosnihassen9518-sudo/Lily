class LilyHome {
  final int id;
  final String name;
  final String timezone;

  const LilyHome({required this.id, required this.name, required this.timezone});

  factory LilyHome.fromJson(Map<String, dynamic> json) => LilyHome(
        id: json['id'] as int,
        name: json['name']?.toString() ?? 'My Home',
        timezone: json['timezone']?.toString() ?? 'Europe/Paris',
      );
}

class LilyRoom {
  final int id;
  final int homeId;
  final String name;
  final String? icon;

  const LilyRoom({required this.id, required this.homeId, required this.name, this.icon});

  factory LilyRoom.fromJson(Map<String, dynamic> json) => LilyRoom(
        id: json['id'] as int,
        homeId: json['home_id'] as int,
        name: json['name']?.toString() ?? 'Room',
        icon: json['icon']?.toString(),
      );
}
