import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'mobile_session_test.dart' show MemoryStore;

void main() {
  test('Offline restart restores identity-bound data without caching credentials', () async {
    SharedPreferences.setMockInitialValues({});
    final token='h.${base64Url.encode(utf8.encode(jsonEncode({'sid':'cache-parent'})))}.s';
    final store=MemoryStore()..data={
      'access_token':token,'refresh_token':'private-refresh-secret',
      'session_expires_at':DateTime.now().add(const Duration(days:90)).toUtc().toIso8601String(),
      'access_expires_at':DateTime.now().add(const Duration(minutes:10)).toUtc().toIso8601String(),
    };
    bool offline=false;
    final client=MockClient((r) async {
      if(offline)return http.Response('unavailable',503);
      if(r.url.path.endsWith('/auth/me'))return http.Response(jsonEncode({'id':1,'email':'cache@test.org'}),200);
      if(r.url.path.endsWith('/devices'))return http.Response(jsonEncode([{'id':1,'serial_number':'CACHE-DEVICE','status':'RESET_PENDING','online':true,'generation':2}]),200);
      return http.Response('[]',200);
    });
    final first=AppState(api:ApiService(client:client,sessionStore:store));
    await first.initialize();
    expect(first.devices,hasLength(1));
    final prefs=await SharedPreferences.getInstance();
    final cache=prefs.getString('session_cache')!;
    expect(cache, isNot(contains(token)));
    expect(cache,isNot(contains('private-refresh-secret')));
    offline=true;
    final second=AppState(api:ApiService(client:client,sessionStore:store));
    await second.initialize();
    expect(second.authenticated,isTrue);
    expect(second.offline,isTrue);
    expect(second.devices.single.status,'RESET_PENDING');
    expect(second.devices.single.online,isFalse);
    expect(second.devices.single.generation,2);
    await second.logout();
    expect(store.data,isNull);
    expect(prefs.getString('session_cache'),isNull);
    first.dispose();second.dispose();
  });
}
