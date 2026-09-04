class Device {
  final int id;
  final String serial;
  final String? name;
  final String model;
  final String status;
  final bool online;
  final DateTime? lastSeen;
  final String? firmware;
  final int? wifiRssi;
  final int? freeStorage;
  final bool lightEnabled;
  final int brightness;
  final int r;
  final int g;
  final int b;
  final bool audioLoaded;
  final bool audioPlaying;
  final int volume;

  Device({
    required this.id,
    required this.serial,
    required this.name,
    required this.model,
    required this.status,
    required this.online,
    required this.lastSeen,
    required this.firmware,
    required this.wifiRssi,
    required this.freeStorage,
    required this.lightEnabled,
    required this.brightness,
    required this.r,
    required this.g,
    required this.b,
    required this.audioLoaded,
    required this.audioPlaying,
    required this.volume,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    final light = (json['light'] as Map?)?.cast<String, dynamic>() ?? {};
    final audio = (json['audio'] as Map?)?.cast<String, dynamic>() ?? {};

    return Device(
      id: json['id'] as int,
      serial: json['serial_number'] as String,
      name: json['name'] as String?,
      model: json['model'] as String? ?? 'LILY-V1',
      status: json['status'] as String? ?? 'OFFLINE',
      online: json['online'] as bool? ?? false,
      lastSeen: json['last_seen'] == null
          ? null
          : DateTime.tryParse(json['last_seen'].toString()),
      firmware: json['firmware_version'] as String?,
      wifiRssi: json['wifi_rssi'] as int?,
      freeStorage: json['free_storage'] as int?,
      lightEnabled: light['enabled'] as bool? ?? false,
      brightness: light['brightness'] as int? ?? 100,
      r: light['r'] as int? ?? 255,
      g: light['g'] as int? ?? 255,
      b: light['b'] as int? ?? 255,
      audioLoaded: audio['loaded'] as bool? ?? false,
      audioPlaying: audio['playing'] as bool? ?? false,
      volume: audio['volume'] as int? ?? 50,
    );
  }

  String get displayName => name?.trim().isNotEmpty == true ? name! : model;
}
