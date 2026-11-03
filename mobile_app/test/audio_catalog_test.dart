import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/models/device.dart';

void main() {
  test('catalog auto and streaming send selection without downloading to phone',
      () async {
    final requests = <http.Request>[];
    final api = ApiService(client: MockClient((r) async {
      requests.add(r);
      return http.Response('{"mqtt_published":true}', 200);
    }));
    await api.selectCatalogAudio(7, 12);
    await api.selectCatalogAudio(7, 14, mode: 'stream');
    expect(requests.map((r) => r.method), ['POST', 'POST']);
    expect(requests.first.url.path, '/api/v1/devices/7/audio/catalog');
    expect(jsonDecode(requests.first.body), {'music_id': 12, 'mode': 'auto'});
    expect(jsonDecode(requests.last.body), {'music_id': 14, 'mode': 'stream'});
  });
  test('MQTT delivery failure is visible', () async {
    final api = ApiService(
        client: MockClient(
            (_) async => http.Response('{"mqtt_published":false}', 200)));
    await expectLater(api.selectCatalogAudio(1, 1), throwsException);
  });
  test('confirmed streaming and download state comes from device telemetry',
      () {
    final d = Device.fromJson({
      'id': 1,
      'serial_number': 'test',
      'generic_state': {
        'audio': {
          'source': 'stream',
          'title': 'Rain',
          'stream_available': true,
          'downloading': true,
          'error': 'Connection lost'
        }
      }
    });
    expect(d.streamAvailable, isTrue);
    expect(d.audioDownloading, isTrue);
    expect(d.audioSource, 'stream');
    expect(d.currentTrackTitle, 'Rain');
    expect(d.audioError, 'Connection lost');
  });
}
