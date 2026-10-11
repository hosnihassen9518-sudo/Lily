import 'dart:convert';
import 'dart:math';

class BleProvisionProtocol {
  static const serviceUuid = '8c9a0001-6f32-4b88-a5c1-1e1d7c6a0000';
  static const infoUuid = '8c9a0002-6f32-4b88-a5c1-1e1d7c6a0000';
  static const commandUuid = '8c9a0003-6f32-4b88-a5c1-1e1d7c6a0000';
  static const statusUuid = '8c9a0004-6f32-4b88-a5c1-1e1d7c6a0000';
  static const maxMessageBytes = 2048;

  static void validateCredentials(String ssid, String password) {
    final ssidLength = utf8.encode(ssid).length;
    final passwordLength = utf8.encode(password).length;
    if (ssidLength < 1 || ssidLength > 32 || ssid.contains('\u0000')) {
      throw const FormatException('Wi-Fi name must contain 1–32 bytes.');
    }
    if ((passwordLength != 0 && (passwordLength < 8 || passwordLength > 63)) ||
        password.contains('\u0000')) {
      throw const FormatException(
          'Wi-Fi password must contain 8–63 bytes, or be empty for an open network.');
    }
  }

  static List<int> encodeProvision(
      {required String requestId,
      required String ssid,
      required String password,
      required String token}) {
    validateCredentials(ssid, password);
    if (requestId.isEmpty || requestId.length > 32 || token.isEmpty) {
      throw const FormatException('Missing or invalid setup session.');
    }
    return encodeCommand({
      'version': 1,
      'request_id': requestId,
      'command': 'provision',
      'ssid': ssid,
      'password': password,
      'pairing_token': token
    });
  }

  static List<int> encodeCommand(Map<String, dynamic> command) {
    final bytes = utf8.encode('${jsonEncode(command)}\n');
    if (bytes.length > maxMessageBytes) {
      throw const FormatException('Setup message is too large.');
    }
    return bytes;
  }

  static List<List<int>> chunkMessage(List<int> bytes, int payloadSize) {
    if (payloadSize < 1) throw ArgumentError.value(payloadSize);
    return [
      for (var i = 0; i < bytes.length; i += payloadSize)
        bytes.sublist(i, min(i + payloadSize, bytes.length))
    ];
  }

  static Map<String, dynamic> decodeObject(List<int> bytes) {
    if (bytes.length > maxMessageBytes) {
      throw const FormatException('Invalid BLE response size.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException(
          'Unsupported Lily BLE firmware. Install the matching firmware.');
    }
    return decoded;
  }

  static Map<String, dynamic>? decodeStatus(List<int> bytes, String requestId) {
    final status = decodeObject(bytes);
    return status['request_id'] == requestId ? status : null;
  }
}
