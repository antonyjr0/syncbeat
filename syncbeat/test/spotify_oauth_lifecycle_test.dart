import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbeat/services/spotify_auth_service.dart';

class _TokenStore implements SpotifyTokenStore {
  SpotifyTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<SpotifyTokens?> read() async => tokens;
  @override
  Future<void> write(SpotifyTokens value) async => tokens = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Windows OAuth lifecycle', () {
    late HttpClient browser;
    late HttpOverrides? originalOverrides;
    setUp(() {
      originalOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      browser = HttpClient();
    });
    tearDown(() {
      browser.close(force: true);
      HttpOverrides.global = originalOverrides;
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> expectPortAvailable() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      await server.close(force: true);
    }

    Future<int> callback(
      Map<String, String> parameters, {
      String path = '/callback',
    }) async {
      final response = await (await browser.getUrl(
        Uri.http('127.0.0.1:8888', path, parameters),
      )).close();
      await response.drain<void>();
      return response.statusCode;
    }

    for (final throwsOnLaunch in [false, true]) {
      test('browser failure releases port; throwing=$throwsOnLaunch', () async {
        final auth = SpotifyAuthService(
          secureTokenStore: _TokenStore(),
          openExternal: (_) async {
            if (throwsOnLaunch) throw StateError('No browser');
            return false;
          },
        );
        await expectLater(auth.signIn(), throwsA(anything));
        await expectPortAvailable();
        // Retrying the same instance must not leave a stale in-progress guard.
        await expectLater(auth.signIn(), throwsA(anything));
        await expectPortAvailable();
      });
    }

    test('callback timeout releases port and permits retry', () async {
      final auth = SpotifyAuthService(
        secureTokenStore: _TokenStore(),
        callbackTimeout: const Duration(milliseconds: 50),
        openExternal: (_) async => true,
      );
      await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
      await expectPortAvailable();
      await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
      await expectPortAvailable();
    });

    test(
      'wrong state never exchanges tokens; unrelated path is ignored',
      () async {
        var exchanges = 0;
        final store = _TokenStore();
        final auth = SpotifyAuthService(
          secureTokenStore: store,
          httpClient: MockClient((_) async {
            exchanges++;
            return http.Response('{}', 400);
          }),
          openExternal: (_) async {
            expect(
              await callback({}, path: '/favicon.ico'),
              HttpStatus.notFound,
            );
            await callback({'state': 'wrong', 'code': 'must-not-exchange'});
            return true;
          },
        );
        await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
        expect(exchanges, 0);
        expect(store.tokens, isNull);
        await expectPortAvailable();
      },
    );

    test('occupied port does not open browser or disrupt its owner', () async {
      final owner = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      var opened = false;
      try {
        final auth = SpotifyAuthService(
          secureTokenStore: _TokenStore(),
          openExternal: (_) async => opened = true,
        );
        await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
        expect(opened, isFalse);
      } finally {
        await owner.close(force: true);
      }
      await expectPortAvailable();
    });

    test(
      'successful login stores tokens and rejects overlapping attempts',
      () async {
        final store = _TokenStore();
        late SpotifyAuthService auth;
        auth = SpotifyAuthService(
          secureTokenStore: store,
          httpClient: MockClient((request) async {
            expect(request.bodyFields['code'], 'valid-code');
            return http.Response(
              '{"access_token":"access","refresh_token":"refresh","expires_in":3600}',
              200,
            );
          }),
          openExternal: (uri) async {
            await expectLater(
              auth.signIn(),
              throwsA(isA<SpotifyAuthException>()),
            );
            await callback({
              'state': uri.queryParameters['state']!,
              'code': 'valid-code',
            });
            return true;
          },
        );
        expect((await auth.signIn()).accessToken, 'access');
        expect(store.tokens?.refreshToken, 'refresh');
        await expectPortAvailable();
      },
    );
  }, skip: !Platform.isWindows);
  test(
    'Android ignores stale login links and releases the subscription on each login',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const events = EventChannel('com.llfbandit.app_links/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      late MockStreamHandlerEventSink sink;
      var listening = Completer<void>();
      var cancelled = 0;
      var exchanges = 0;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, value) {
            sink = value;
            listening.complete();
          },
          onCancel: (_) {
            cancelled++;
          },
        ),
      );
      addTearDown(() => messenger.setMockStreamHandler(events, null));
      final auth = SpotifyAuthService(
        secureTokenStore: _TokenStore(),
        httpClient: MockClient((_) async {
          exchanges++;
          return http.Response(
            '{"access_token":"access","expires_in":3600}',
            200,
          );
        }),
        openExternal: (uri) async {
          await listening.future;
          sink.success(
            'amazfitmusicsync://callback?state=previous-login&code=stale',
          );
          await Future<void>.delayed(Duration.zero);
          expect(exchanges, 0);
          sink.success(
            Uri(
              scheme: 'amazfitmusicsync',
              host: 'callback',
              queryParameters: {
                'state': uri.queryParameters['state']!,
                'code': 'current-code',
              },
            ).toString(),
          );
          return true;
        },
      );
      expect((await auth.signIn()).accessToken, 'access');
      expect(cancelled, 1);
      listening = Completer<void>();
      exchanges = 0;
      expect((await auth.signIn()).accessToken, 'access');
      expect(exchanges, 1);
      expect(cancelled, 2);
    },
  );
}
