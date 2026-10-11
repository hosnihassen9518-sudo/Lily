import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wifi_iot/wifi_iot.dart';
import '../config.dart';

class ProvisionService {
  ProvisionService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<String> connectWithPairingToken(
    String ssid,
    Future<String> Function() createPairingToken,
  ) async {
    // A LAN backend cannot be reached after switching to the ESP32 setup AP.
    final token = await createPairingToken();
    if (!await connectToDeviceAp(ssid)) {
      throw Exception('Could not join the Lily setup network.');
    }
    return token;
  }

  Future<List<String>> scanLilyNetworks() async {
    try {
      final networks = await WiFiForIoTPlugin.loadWifiList();
      final names = <String>{};
      for (final network in networks) {
        final ssid = network.ssid?.trim() ?? '';
        if (ssid.toUpperCase().startsWith('LILY-')) names.add(ssid);
      }
      final result = names.toList()..sort();
      return result;
    } catch (e) {
      throw Exception(
        'Could not scan Wi-Fi networks. Enable Wi-Fi and location permission, then try again.',
      );
    }
  }

  Future<bool> connectToDeviceAp(String ssid) async {
    if (!ssid.toUpperCase().startsWith('LILY-')) {
      throw Exception('Only Lily setup networks can be provisioned.');
    }
    final connected = await WiFiForIoTPlugin.connect(
      ssid,
      security: NetworkSecurity.NONE,
      joinOnce: true,
      withInternet: false,
    );
    debugPrint('Lily setup: Wi-Fi join completed=$connected');
    if (!connected) return false;
    try {
      if (!await WiFiForIoTPlugin.forceWifiUsage(true)) {
        throw Exception('Could not route requests through the Lily setup Wi-Fi.');
      }
      debugPrint('Lily setup: Wi-Fi routing bound successfully');
    } catch (_) {
      await disconnectFromDeviceAp();
      rethrow;
    }
    return true;
  }

  Future<void> disconnectFromDeviceAp() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
    } finally {
      try {
      await WiFiForIoTPlugin.disconnect();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    Object? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .get(Uri.parse('${AppConfig.esp32ProvisionUrl}/info'))
            .timeout(const Duration(seconds: 7));
        if (response.statusCode != 200) {
          throw Exception('The Lily device returned HTTP ${response.statusCode}.');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      } on TimeoutException catch (error) {
        lastFailure = error;
        debugPrint('Lily setup: /info attempt ${attempt + 1}: $error');
        // Android may finish routing shortly after the Wi-Fi join completes.
      } on http.ClientException catch (error) {
        lastFailure = error;
        debugPrint('Lily setup: /info attempt ${attempt + 1}: $error');
        // Retry a transient local connection failure, never a provisioning POST.
      }
      if (attempt < 2) await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw Exception('Connected to setup Wi-Fi, but the ESP32 did not answer at '
        '${AppConfig.esp32ProvisionUrl}/info. Last connection error: $lastFailure');
  }

  Future<List<Map<String, dynamic>>> getNearbyHomeNetworks() async {
    final response = await _client
        .get(Uri.parse('${AppConfig.esp32ProvisionUrl}/networks'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('The Lily device could not scan nearby Wi-Fi networks.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['networks'] as List<dynamic>? ?? const [];
    final unique = <String, Map<String, dynamic>>{};
    for (final raw in list) {
      final item = (raw as Map).cast<String, dynamic>();
      final ssid = item['ssid']?.toString().trim() ?? '';
      if (ssid.isEmpty) continue;
      final previous = unique[ssid];
      final currentRssi = item['rssi'] as int? ?? -999;
      final previousRssi = previous?['rssi'] as int? ?? -999;
      if (previous == null || currentRssi > previousRssi) unique[ssid] = item;
    }
    final result = unique.values.toList();
    result.sort((a, b) => ((b['rssi'] as int?) ?? -999).compareTo((a['rssi'] as int?) ?? -999));
    return result;
  }

  Future<void> provisionWifi({
    required String wifiSsid,
    required String wifiPassword,
    required String pairingToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('${AppConfig.esp32ProvisionUrl}/provision'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'ssid': wifiSsid,
            'password': wifiPassword,
            'pairing_token': pairingToken,
          }),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Wi-Fi provisioning failed.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {}
      throw Exception(message);
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
      http.MultipartFile.fromBytes('file', bytes, filename: 'current.mp3'),
    );

    final response = await request.send().timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Device upload failed: $body');
    }
  }
}
