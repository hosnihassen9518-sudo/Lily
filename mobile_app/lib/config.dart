class AppConfig {
  // For Android emulator use 10.0.2.2 instead of 127.0.0.1.
  // For a physical phone, set this to the computer/server LAN IP.
  static const backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://192.168.1.100:8000/api/v1',
  );

  static const esp32ProvisionUrl = 'http://192.168.4.1';
}
