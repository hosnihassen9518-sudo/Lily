import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:lily_mobile/services/api_service.dart';
import 'package:lily_mobile/screens/music_screen.dart';
import 'package:lily_mobile/models/music_track.dart';
import 'package:lily_mobile/state/app_state.dart';
import 'mobile_session_test.dart' show MemoryStore;

void main() {
  test(
      'multipart retries once with refreshed bearer after unauthorized response',
      () async {
    final expiry =
        DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    final accessExpiry = DateTime.now()
        .add(const Duration(minutes: 15))
        .toUtc()
        .toIso8601String();
    final store = MemoryStore()
      ..data = {
        'access_token': 'old',
        'refresh_token': 'r' * 64,
        'session_expires_at': expiry,
        'access_expires_at': accessExpiry
      };
    var uploads = 0, refreshes = 0;
    final api = ApiService(
        sessionStore: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/refresh')) {
            refreshes++;
            return http.Response(
                jsonEncode({
                  'access_token': 'new',
                  'refresh_token': 's' * 64,
                  'session_expires_at': expiry,
                  'access_expires_at': accessExpiry
                }),
                200);
          }
          uploads++;
          expect(r.body, contains('ID3-song'));
          expect(r.headers['Authorization'],
              uploads == 1 ? 'Bearer old' : 'Bearer new');
          return uploads == 1
              ? http.Response('{}', 401)
              : http.Response('{"id":1,"title":"Song","is_private":true}', 200);
        }));
    await api.restoreSession();
    await api.uploadPrivateMusic(
        filename: 'song.mp3',
        bytes: Uint8List.fromList(utf8.encode('ID3-song')));
    expect(uploads, 2);
    expect(refreshes, 1);
  });
  testWidgets('selected phone file uploads and appears only in My files',
      (tester) async {
    var calls = 0;
    final state = AppState(api: ApiService(client: MockClient((r) async {
      calls++;
      expect(r.url.path, '/api/v1/music/private');
      return http.Response('{"id":2,"title":"My rain","is_private":true}', 200);
    })));
    final screen = MusicScreen(
        pickAudio: () async => PlatformFile(
            name: 'rain.mp3',
            size: 8,
            readStream: Stream.value(utf8.encode('ID3-song'))));
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state, child: MaterialApp(home: Scaffold(body: screen))));
    await tester.tap(find.text('Choose MP3 from phone'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(state.music.single.isPrivate, isTrue);
    expect(find.text('My rain'), findsOneWidget);
    expect(find.textContaining('saved in My files'), findsOneWidget);
  });
  testWidgets(
      'changing servers while the picker stream closes never uploads old bytes',
      (tester) async {
    final stream = StreamController<List<int>>();
    var calls = 0;
    final api = ApiService(client: MockClient((r) async {
      calls++;
      return http.Response('{}', 200);
    }));
    final state = AppState(api: api);
    final screen = MusicScreen(
        pickAudio: () async =>
            PlatformFile(name: 'rain.mp3', size: 8, readStream: stream.stream));
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state, child: MaterialApp(home: Scaffold(body: screen))));
    await tester.tap(find.text('Choose MP3 from phone'));
    await tester.pump();
    stream.add(utf8.encode('ID3-song'));
    await tester.pump();
    api.baseUrl = 'http://new-server.test/api/v1';
    await stream.close();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(state.music, isEmpty);
  });
  test('private upload uses multipart and authentication', () async {
    final api = ApiService(client: MockClient((r) async {
      expect(r.method, 'POST');
      expect(r.url.path, '/api/v1/music/private');
      expect(r.headers['Authorization'], 'Bearer test-token');
      expect(r.headers['content-type'], startsWith('multipart/form-data'));
      expect(r.body, contains('Rain.mp3'));
      expect(r.body, contains('ID3-song'));
      return http.Response(
          jsonEncode({'id': 4, 'title': 'Rain', 'is_private': true}), 200);
    }))
      ..token = 'test-token';
    final track = await api.uploadPrivateMusic(
        filename: 'Rain.mp3',
        bytes: Uint8List.fromList(utf8.encode('ID3-song')));
    expect(track.isPrivate, isTrue);
  });
  test('upload cannot return a track into a switched server session', () async {
    final release = Completer<http.Response>();
    final api = ApiService(client: MockClient((_) => release.future));
    final pending = api.uploadPrivateMusic(
        filename: 'a.mp3', bytes: Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    api.baseUrl = 'http://different.test/api/v1';
    release.complete(http.Response('{"id":1,"title":"Old"}', 200));
    await expectLater(pending, throwsStateError);
  });
  testWidgets(
      'catalog and private files are separate and picker cancellation is harmless',
      (tester) async {
    var picked = 0;
    final state = AppState()
      ..music = [
        MusicTrack.fromJson({'id': 1, 'title': 'Public track'}),
        MusicTrack.fromJson(
            {'id': 2, 'title': 'Private track', 'is_private': true})
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child:
            MaterialApp(home: Scaffold(body: MusicScreen(pickAudio: () async {
          picked++;
          return null;
        })))));
    expect(find.text('Server catalog'), findsOneWidget);
    expect(find.text('My files'), findsOneWidget);
    await tester.tap(find.text('My files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose MP3 from phone'));
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(tester.takeException(), isNull);
  });
}
