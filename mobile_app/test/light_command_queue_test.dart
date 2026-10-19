import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lily_mobile/services/light_command_queue.dart';

void main() {
  test('release cancels debounce and avoids duplicate commands', () async {
    final sent = <Map<String, Object?>>[];
    final queue = LightCommandQueue(
        send: (v) async {
          sent.add(v);
        },
        onError: (e) => fail('$e'),
        debounce: const Duration(milliseconds: 10),
        minimumInterval: const Duration(milliseconds: 15));
    queue.enqueue({'r': 1});
    await queue.enqueue({'r': 1}, immediate: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sent, [
      {'r': 1}
    ]);
  });
  test('latest pending value survives caller leaving the screen', () async {
    final sent = <Map<String, Object?>>[];
    final queue = LightCommandQueue(
        send: (v) async {
          sent.add(v);
        },
        onError: (e) => fail('$e'),
        debounce: const Duration(milliseconds: 5),
        minimumInterval: const Duration(milliseconds: 20));
    await queue.enqueue({'r': 1}, immediate: true);
    queue.enqueue({'r': 2}, immediate: true);
    queue.enqueue({'r': 3}, immediate: true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sent, [
      {'r': 1},
      {'r': 3}
    ]);
  });
  test('queue is shared across screens and survives access-token rotation',
      () async {
    final sent = <Map>[];
    final api = ApiService(client: MockClient((r) async {
      sent.add(jsonDecode(r.body) as Map);
      return http.Response('{"mqtt_published":true}', 200);
    }));
    String token(String signature) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({
              'sid': 'same-session'
            })))}.$signature';
    api.token = token('old');
    final first = api.lightCommandsFor(3, onError: (e) => fail('$e'));
    await first.enqueue({'enabled': true, 'r': 1}, immediate: true);
    api.token = token('refreshed');
    final reopened = api.lightCommandsFor(3, onError: (e) => fail('$e'));
    expect(identical(first, reopened), isTrue);
    await reopened.enqueue({'enabled': true, 'r': 2}, immediate: true);
    expect(sent.last['r'], 2);
    final oldServerQueue = reopened;
    api.baseUrl = 'http://other.test/api/v1';
    await oldServerQueue.enqueue({'enabled': true, 'r': 3}, immediate: true);
    expect(sent.length, 2);
  });
  test('completed intent does not override new authoritative device state',
      () async {
    final sent = <Map<String, Object?>>[];
    final queue = LightCommandQueue(
        send: (v) async {
          sent.add(v);
        },
        onError: (e) => fail('$e'),
        minimumInterval: Duration.zero);
    await queue.enqueue({'enabled': true}, immediate: true);
    expect(queue.latestIntent, isNull);
    queue.reconcile();
    await queue.enqueue({'enabled': true}, immediate: true);
    expect(sent.length, 2);
  });
}
