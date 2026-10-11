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
  final int? homeId;
  final int? roomId;
  final int? deviceTypeId;
  final String? deviceTypeKey;
  final String? deviceTypeName;
  final List<String> capabilities;
  final Map<String, dynamic> genericState;

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
    required this.homeId,
    required this.roomId,
    required this.deviceTypeId,
    required this.deviceTypeKey,
    required this.deviceTypeName,
    required this.capabilities,
    required this.genericState,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    final light = (json['light'] as Map?)?.cast<String, dynamic>() ?? {};
    final audio = (json['audio'] as Map?)?.cast<String, dynamic>() ?? {};
    final smart = (json['smart_home'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawCaps = smart['capabilities'] as List<dynamic>? ?? const [];

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
      homeId: smart['home_id'] as int?,
      roomId: smart['room_id'] as int?,
      deviceTypeId: smart['device_type_id'] as int?,
      deviceTypeKey: smart['device_type_key']?.toString(),
      deviceTypeName: smart['device_type_name']?.toString(),
      capabilities: rawCaps.map((e) => e.toString()).toList(),
      genericState:
          (json['generic_state'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  String get displayName =>
      name?.trim().isNotEmpty == true ? name! : (deviceTypeName ?? model);
  bool hasCapability(String capability) =>
      capabilities.isEmpty || capabilities.contains(capability);
  bool get supportsLight =>
      capabilities.contains('light') ||
      (hasCapability('power') &&
          (hasCapability('brightness') || hasCapability('rgb')));
  bool get supportsAudio => hasCapability('audio');
  String? get currentTrackTitle =>
      genericState['current_track_title']?.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'serial_number': serial,
        'name': name,
        'model': model,
        'status': status,
        'online': online,
        'last_seen': lastSeen?.toIso8601String(),
        'firmware_version': firmware,
        'wifi_rssi': wifiRssi,
        'free_storage': freeStorage,
        'light': {
          'enabled': lightEnabled,
          'brightness': brightness,
          'r': r,
          'g': g,
          'b': b
        },
        'audio': {
          'loaded': audioLoaded,
          'playing': audioPlaying,
          'volume': volume
        },
        'smart_home': {
          'home_id': homeId,
          'room_id': roomId,
          'device_type_id': deviceTypeId,
          'device_type_key': deviceTypeKey,
          'device_type_name': deviceTypeName,
          'capabilities': capabilities
        },
        'generic_state': genericState,
      };
}
