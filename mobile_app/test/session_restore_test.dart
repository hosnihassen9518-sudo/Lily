import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Temporary server failure retains saved login', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'existing-token'});
    final state = AppState(
        api: ApiService(
            client:
                MockClient((_) async => http.Response('unavailable', 503))));
    await state.initialize();
    expect(state.authenticated, isTrue);
    expect((await SharedPreferences.getInstance()).getString('access_token'),
        'existing-token');
    expect(state.error, isNotNull);
  });
}
