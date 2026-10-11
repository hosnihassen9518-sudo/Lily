class BackendSettings {
  final String host;
  final int port;
  final String scheme;

  const BackendSettings._(this.host, this.port, this.scheme);

  static String? hostError(String value) {
    final host = value.trim();
    final labels = host.split('.');
    if (host.isEmpty ||
        host.length > 253 ||
        labels.any((label) =>
            !RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
                .hasMatch(label))) {
      return 'Enter an IP address or hostname without http:// or a path.';
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(host) &&
        (labels.length != 4 ||
            labels.any((label) => (int.tryParse(label) ?? 256) > 255))) {
      return 'Enter a valid IPv4 address.';
    }
    return null;
  }

  static String? portError(String value) {
    final port = int.tryParse(value.trim());
    return port == null || port < 1 || port > 65535
        ? 'Enter a port from 1 to 65535.'
        : null;
  }

  factory BackendSettings.validated(
      {required String host, required String port, required String scheme}) {
    final error = hostError(host) ?? portError(port);
    if (error != null) throw FormatException(error);
    if (scheme != 'http' && scheme != 'https') {
      throw const FormatException('Choose HTTP or HTTPS.');
    }
    return BackendSettings._(
        host.trim().toLowerCase(), int.parse(port.trim()), scheme);
  }

  factory BackendSettings.fromUrl(String value) {
    final uri = Uri.parse(value);
    return BackendSettings.validated(
        host: uri.host, port: '${uri.port}', scheme: uri.scheme);
  }

  String get baseUrl => '$scheme://$host:$port/api/v1';
}
