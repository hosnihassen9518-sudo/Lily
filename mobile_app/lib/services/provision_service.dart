import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:wifi_iot/wifi_iot.dart';
import '../config.dart';

class ProvisionService {
  Future<bool> connectToDeviceAp(String ssid) async {
    // ESP32 provisioning AP is open by default in firmware V0.4.
    // For production, add a per-device AP password or QR-based setup secret.
    return WiFiForIoTPlugin.connect(
      ssid,
      security: NetworkSecurity.NONE,
      joinOnce: true,
      withInternet: false,
    );
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final response = await http
        .get(Uri.parse('${AppConfig.esp32ProvisionUrl}/info'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Could not contact the Lily device.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> provisionWifi({
    required String wifiSsid,
    required String wifiPassword,
    required String pairingToken,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.esp32ProvisionUrl}/provision'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'ssid': wifiSsid,
            'password': wifiPassword,
            'pairing_token': pairingToken,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Wi-Fi provisioning failed.');
    }
  }

  Future<void> uploadMp3({
    required Uint8List bytes,
    required String checksum,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.esp32ProvisionUrl}/audio'),
    );

    request.fields['sha256'] = checksum;
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'current.mp3',
      ),
    );

    final response = await request.send().timeout(const Duration(minutes: 3));

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Device upload failed: $body');
    }
  }
}
