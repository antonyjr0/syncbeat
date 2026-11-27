import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbeat/features/zepp/zepp_account.dart';
import 'package:syncbeat/features/zepp/zepp_client.dart';

const watch = ZeppDevice('Test watch', 'AA:BB:CC:DD:EE:FF');
const key = '00112233445566778899aabbccddeeff';

Map<String, dynamic> devices({
  String address = 'aa-bb-cc-dd-ee-ff',
  dynamic info,
}) => {
  'items': [
    {
      'macAddress': address,
      'additionalInfo':
          info ?? jsonEncode({'auth_key': '0x${key.toUpperCase()}'}),
    },
  ],
};

http.Response tokens() => http.Response(
  '',
  303,
  headers: {
    'location':
        'https://s3-us-west-2.amazonaws.com/hm-registration/successsignin.html?access=synthetic-access&refresh=synthetic-refresh',
  },
);
http.Response login() => http.Response(
  jsonEncode({
    'token_info': {
      'user_id': 42,
      'app_token': 'synthetic-app',
      'login_token': 'synthetic-login',
    },
  }),
  200,
);

void main() {
  test(
    'matches full normalized MAC and imports only the selected auth_key',
    () {
      expect(selectZeppAccountKey(devices(), watch.address), key);
      expect(
        selectZeppAccountKey(devices(info: {'auth_key': key}), watch.address),
        key,
      );
      expect(
        () => selectZeppAccountKey(
          devices(address: 'AA:BB:CC:DD:EE:00'),
          watch.address,
        ),
        throwsA(isA<ZeppException>()),
      );
      expect(
        () => selectZeppAccountKey({
          'items': [...devices()['items'], ...devices()['items']],
        }, watch.address),
        throwsA(isA<ZeppException>()),
      );
      for (final info in [
        'not json',
        {'btKey': key},
        {'auth_key': 'bad'},
        {'auth_key': 123},
        null,
      ]) {
        final response = {
          'items': [
            {'macAddress': watch.address, 'additionalInfo': info},
          ],
        };
        expect(
          () => selectZeppAccountKey(response, watch.address),
          throwsA(isA<ZeppException>()),
        );
      }
    },
  );

  test(
    'web identity throughout authentication, no mobile login or logout, closes locally',
    () async {
      final calls = <http.Request>[];
      final client = _TrackedClient((request) async {
        calls.add(request);
        expect(request.followRedirects, isFalse);
        expect(request.url.scheme, 'https');
        expect(request.url.path, isNot(contains('/logout')));
        if (request.url.path.endsWith('/tokens')) {
          expect(request.url.host, 'api-user.huami.com');
          expect(request.url.pathSegments, [
            'registrations',
            'test@example.com',
            'tokens',
          ]);
          expect(request.headers['app_name'], 'com.huami.webapp');
          expect(request.headers['appplatform'], 'web');
          final fields = Uri.splitQueryString(request.body);
          expect(fields['password'], 'synthetic-password');
          expect(fields['name'], 'test@example.com');
          expect(fields['token'], 'access');
          return tokens();
        }
        if (request.url.path.endsWith('/login')) {
          expect(request.url.host, 'api-mifit.zepp.com');
          final fields = Uri.splitQueryString(request.body);
          expect(fields['code'], 'synthetic-access');
          expect(fields['device_model'], 'web');
          expect(fields['device_id'], startsWith('web_'));
          expect(fields['app_name'], 'com.huami.webapp');
          expect(fields['source'], 'com.huami.webapp');
          expect(request.headers['appplatform'], 'web');
          return login();
        }
        if (request.url.path.endsWith('/app_tokens')) {
          expect(request.headers['app_name'], 'com.huami.webapp');
          expect(request.url.queryParameters['login_token'], 'synthetic-login');
          return http.Response(
            '{"token_info":{"app_token":"synthetic-app"}}',
            200,
          );
        }
        if (request.url.path.endsWith('/devices')) {
          expect(request.url.host, 'api-mifit.zepp.com');
          expect(request.headers['apptoken'], 'synthetic-app');
          expect(request.url.queryParametersAll['r']!.length, 2);
          return http.Response(jsonEncode(devices()), 200);
        }
        throw StateError('Unexpected endpoint');
      });
      final result = await ZeppAccount(clientFactory: () => client).recoverKey(
        email: 'test@example.com',
        password: 'synthetic-password',
        device: watch,
      );
      expect(result, key);
      expect(calls.length, 4);
      expect(client.closed, isTrue);
    },
  );

  for (final status in [401, 429, 500]) {
    test(
      'token refusal $status stops immediately without exposing response or retry',
      () async {
        var requests = 0;
        final client = _TrackedClient((_) async {
          requests++;
          return http.Response('PRIVATE-RESPONSE', status);
        });
        try {
          await ZeppAccount(clientFactory: () => client).recoverKey(
            email: 'test@example.com',
            password: 'secret',
            device: watch,
          );
          fail('Expected failure');
        } on ZeppException catch (error) {
          expect(error.message, isNot(contains('PRIVATE-RESPONSE')));
          if (status == 429) expect(error.message, contains('Troppi accessi'));
        }
        expect(requests, 1);
        expect(client.closed, isTrue);
      },
    );
  }

  test('unexpected token redirect never contacts its destination', () async {
    var requests = 0;
    final client = _TrackedClient((_) async {
      requests++;
      return http.Response(
        '',
        303,
        headers: {'location': 'https://example.com/?access=PRIVATE'},
      );
    });
    await expectLater(
      ZeppAccount(clientFactory: () => client).recoverKey(
        email: 'test@example.com',
        password: 'secret',
        device: watch,
      ),
      throwsA(isA<ZeppException>()),
    );
    expect(requests, 1);
    expect(client.closed, isTrue);
  });

  test(
    'device error closes locally without logout or mobile fallback',
    () async {
      final paths = <String>[];
      final client = _TrackedClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/tokens')) return tokens();
        if (request.url.path.endsWith('/login')) return login();
        if (request.url.path.endsWith('/app_tokens')) {
          return http.Response(
            '{"token_info":{"app_token":"synthetic-app"}}',
            200,
          );
        }
        if (request.url.path.endsWith('/devices')) {
          return http.Response('{"items":[]}', 200);
        }
        return http.Response('PRIVATE', 500);
      });
      await expectLater(
        ZeppAccount(clientFactory: () => client).recoverKey(
          email: 'test@example.com',
          password: 'secret',
          device: watch,
        ),
        throwsA(isA<ZeppException>()),
      );
      expect(paths.last, '/users/42/devices');
      expect(paths.any((p) => p.contains('/logout')), isFalse);
      expect(paths.length, 4);
      expect(client.closed, isTrue);
    },
  );

  test(
    'registration JSON response supported without redirect or mobile fallback',
    () async {
      final paths = <String>[];
      final client = _TrackedClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/tokens')) {
          return http.Response('{"access":"synthetic-access"}', 200);
        }
        if (request.url.path.endsWith('/login')) return login();
        if (request.url.path.endsWith('/app_tokens')) {
          return http.Response(
            '{"token_info":{"app_token":"synthetic-app"}}',
            200,
          );
        }
        return http.Response(jsonEncode(devices()), 200);
      });
      expect(
        await ZeppAccount(clientFactory: () => client).recoverKey(
          email: 'test@example.com',
          password: 'synthetic-password',
          device: watch,
        ),
        key,
      );
      expect(paths.length, 4);
      expect(
        paths.any(
          (p) => p.startsWith('/v2/registrations') || p.contains('/logout'),
        ),
        isFalse,
      );
      expect(client.closed, isTrue);
    },
  );

  test('timeout does not retry and closes the HTTP client', () async {
    var count = 0;
    final pending = Completer<http.Response>();
    final client = _TrackedClient((_) {
      count++;
      return pending.future;
    });
    await expectLater(
      ZeppAccount(
        clientFactory: () => client,
        requestTimeout: const Duration(milliseconds: 10),
      ).recoverKey(
        email: 'test@example.com',
        password: 'secret',
        device: watch,
      ),
      throwsA(
        isA<ZeppException>().having(
          (e) => e.message,
          'message',
          contains('in tempo'),
        ),
      ),
    );
    expect(count, 1);
    expect(client.closed, isTrue);
    pending.complete(http.Response('', 401));
  });

  test(
    'response size limit fails closed; malformed JSON does not expose body',
    () async {
      for (final body in ['x' * (1024 * 1024 + 1), 'PRIVATE-NOT-JSON']) {
        final client = _TrackedClient(
          (request) async => request.url.path.endsWith('/tokens')
              ? tokens()
              : http.Response(body, 200),
        );
        await expectLater(
          ZeppAccount(clientFactory: () => client).recoverKey(
            email: 'test@example.com',
            password: 'secret',
            device: watch,
          ),
          throwsA(
            isA<ZeppException>().having(
              (e) => e.message,
              'message',
              isNot(contains('PRIVATE')),
            ),
          ),
        );
        expect(client.closed, isTrue);
      }
    },
  );
}

class _TrackedClient extends MockClient {
  _TrackedClient(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}
