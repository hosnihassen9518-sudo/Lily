import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:lily_mobile/services/api_service.dart';

void main() {
  test('Removal stays pending until backend confirms completion', () async {
    final api = ApiService(client: MockClient((r) async {
      if (r.url.path.endsWith('/removal')) {
        return http.Response(
            jsonEncode(
                {'operation_id': 'op', 'status': 'pending', 'device_id': 1}),
            200);
      }
      return http.Response(
          jsonEncode(
              {'operation_id': 'op', 'status': 'completed', 'device_id': 1}),
          200);
    }));
    expect((await api.removeDevice(1))['status'], 'pending');
    expect((await api.getDeviceOperation('op'))['status'], 'completed');
  });
}
