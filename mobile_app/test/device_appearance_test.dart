import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lily_mobile/main.dart';
import 'package:lily_mobile/models/device.dart';
import 'package:lily_mobile/models/lily_appearance.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'package:lily_mobile/widgets/device_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _device(int id, String model, String theme, String image,
        List<String> capabilities) =>
    {
      'id': id,
      'serial_number': 'TEST-$id',
      'smart_home': {
        'model_key': model,
        'model_name': model,
        'theme_key': theme,
        'image_key': image,
        'capabilities': capabilities,
      },
    };

final _light = _device(1, 'Lily Light', 'kids', 'lily-light', ['light']);
final _speaker = _device(
    2, 'Lily Light + Speaker', 'kids', 'lily-speaker', ['light', 'audio']);
final _gaming = _device(3, 'Gaming Light', 'gaming', 'gaming-light', ['light']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appearance follows owned models and persists per account and server',
      () async {
    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});
    AppState stateFor(int user, {String? server}) {
      final api = ApiService(client: MockClient((request) async {
        final path = request.url.path;
        final Object result = path.endsWith('/auth/me')
            ? {'id': user}
            : path.endsWith('/devices')
                ? [_light, _speaker, _gaming]
                : [];
        return http.Response(jsonEncode(result), 200);
      }));
      if (server != null) api.baseUrl = server;
      return AppState(api: api);
    }

    final original = stateFor(1);
    await original.initialize();
    expect(original.availableAppearances, LilyAppearance.values);
    expect(original.appearance, LilyAppearance.kids);
    await original.selectAppearance(LilyAppearance.gaming);
    expect(original.appearance, LilyAppearance.gaming);
    original.dispose();

    final restored = stateFor(1);
    await restored.initialize();
    expect(restored.appearance, LilyAppearance.gaming);
    restored.devices = [Device.fromJson(_light), Device.fromJson(_speaker)];
    expect(restored.appearance, LilyAppearance.kids);
    expect(restored.availableAppearances, [LilyAppearance.kids]);
    restored.devices = [Device.fromJson(_gaming)];
    expect(restored.appearance, LilyAppearance.gaming);
    restored.devices = [];
    expect(restored.appearance, LilyAppearance.kids);
    restored.dispose();

    final otherAccount = stateFor(2);
    await otherAccount.initialize();
    expect(otherAccount.appearance, LilyAppearance.kids);
    otherAccount.dispose();

    final otherServer = stateFor(1, server: 'http://other.local:6100/api/v1');
    await otherServer.initialize();
    expect(otherServer.appearance, LilyAppearance.kids);
    otherServer.dispose();
  });

  testWidgets('Appearance applies gaming without changing kids device pictures',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState()
      ..profile = {'id': 1}
      ..devices = [_light, _speaker, _gaming].map(Device.fromJson).toList();
    state.api.token = 'test-token';
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: state, child: const LilyApp()));
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Gaming'));
    await tester.pumpAndSettle();
    expect(state.appearance, LilyAppearance.gaming);
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Your gaming setup'), findsOneWidget);
    final lightContext = tester.element(find.text('Lily Light'));
    expect(Theme.of(lightContext).brightness, Brightness.dark);

    String assetFor(String title) {
      final card = find.ancestor(
          of: find.text(title), matching: find.byType(DeviceCard));
      final image = tester.widget<Image>(
          find.descendant(of: card, matching: find.byType(Image)));
      return (image.image as AssetImage).assetName;
    }

    expect(assetFor('Lily Light'), 'assets/branding/lily_cloud.png');
    expect(
        assetFor('Lily Light + Speaker'), 'assets/branding/lily_speaker.png');
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  test(
      'catalog presentation survives cache serialization and legacy model lookup',
      () {
    final fromCache = Device.fromJson(Device.fromJson(_speaker).toJson());
    expect(fromCache.modelKey, 'Lily Light + Speaker');
    expect(fromCache.catalogName, 'Lily Light + Speaker');
    expect(fromCache.imageKey, 'lily-speaker');
    expect(fromCache.appearanceKey, 'kids');
    final legacy =
        Device.fromJson({'id': 1, 'serial_number': 'OLD', 'model': 'Lily V2'});
    expect(legacy.catalogName, 'Lily Light + Speaker');
    expect(legacy.appearanceKey, 'kids');
    expect(legacy.productImageKey, 'lily-speaker');
  });
}
