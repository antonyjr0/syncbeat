import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'zepp_client.dart';
import 'zepp_diagnostics.dart';

/// Non-public Zepp WEB login, based on dreeve-zepp-connector (AGPL-3.0).
/// Mobile login can displace the official phone app. Never fall back to it or
/// call account logout. Only the selected watch key is persisted by the caller.
/// See the bundled notices and docs/zepp-account-fattibilita.md.
class ZeppAccount {
  ZeppAccount({
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  final Duration requestTimeout;
  static const _version = '151689_9.12.5';
  static const _agent = 'Zepp/9.12.5 (Pixel 4; Android 12; Density/2.75)';
  static const _contentType =
      'application/x-www-form-urlencoded; charset=UTF-8';
  static const _webApp = 'com.huami.webapp';
  static const _redirect =
      'https://s3-us-west-2.amazonaws.com/hm-registration/successsignin.html';
  static const _webAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  Future<String> recoverKey({
    required String email,
    required String password,
    required ZeppDevice device,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const ZeppException(
        'Inserisci email e password del tuo account Zepp.',
      );
    }
    if (_mac(device.address) == null) {
      throw const ZeppException('Scegli prima un orologio abbinato.');
    }
    final client = _clientFactory();
    zeppDiagnostic('ACCOUNT_RECOVERY_START');
    try {
      final tokenResponse = await _request(
        client,
        'POST',
        Uri(
          scheme: 'https',
          host: 'api-user.huami.com',
          pathSegments: ['registrations', email.trim(), 'tokens'],
        ),
        headers: _webHeaders,
        body: _form({
          'name': email.trim(),
          'state': 'REDIRECTION',
          'client_id': 'HuaMi',
          'password': password,
          'redirect_uri': _redirect,
          'json_response': 'true',
          'token': 'access',
          'country_code': 'US',
        }),
      );
      if (tokenResponse.statusCode != 303 && tokenResponse.statusCode != 200) {
        if (tokenResponse.statusCode == 429) throw _rateLimited;
        if (tokenResponse.statusCode >= 500) {
          throw const ZeppException(
            'Il servizio Zepp non è disponibile. Riprova più tardi.',
          );
        }
        throw const ZeppException(
          'Accesso Zepp non riuscito. Controlla email e password. '
          'Se usi Google o Apple, serve una password Zepp associata allo stesso account.',
        );
      }
      String? access;
      final locationHeader = tokenResponse.headers['location'];
      if (locationHeader != null) {
        final location = Uri.tryParse(locationHeader);
        // Read the code locally. Never follow this redirect.
        if (location == null ||
            location.scheme != 'https' ||
            location.host != 's3-us-west-2.amazonaws.com' ||
            location.path != '/hm-registration/successsignin.html') {
          throw _unsupported;
        }
        access = _nonempty(location.queryParameters['access']);
      } else if (tokenResponse.statusCode == 200) {
        final data = jsonDecode(utf8.decode(tokenResponse.bodyBytes));
        if (data is Map) access = _nonempty(data['access'] ?? data['code']);
      }
      if (access == null || access.isEmpty) throw _unsupported;
      zeppDiagnostic('ACCOUNT_TOKENS_OK');
      final login = await _jsonRequest(
        client,
        'POST',
        Uri.https('api-mifit.zepp.com', '/v2/client/login'),
        headers: _webHeaders,
        body: _form({
          'code': access,
          'device_id': 'web_${_uuid()}',
          'device_model': 'web',
          'app_version': '1.0.0',
          'dn':
              'api-mifit.zepp.com,api-user.zepp.com,api-watch.zepp.com,auth.zepp.com',
          'third_name': 'huami',
          'source': _webApp,
          'app_name': _webApp,
          'country_code': 'US',
          'grant_type': 'access_token',
          'allow_registration': 'false',
        }),
      );
      final info = login['token_info'];
      if (info is! Map<String, dynamic>) throw _unsupported;
      final loginToken = _nonempty(info['login_token']);
      final userId = _nonempty(info['user_id']);
      if (loginToken == null || userId == null) {
        throw _unsupported;
      }
      zeppDiagnostic('ACCOUNT_WEB_LOGIN_OK');
      final appTokens = await _jsonRequest(
        client,
        'GET',
        Uri.https('api-mifit.zepp.com', '/v1/client/app_tokens', {
          'app_name': _webApp,
          'dn': 'api-mifit.zepp.com,api-user.zepp.com,auth.zepp.com',
          'login_token': loginToken,
        }),
        headers: _webHeaders,
      );
      final appInfo = appTokens['token_info'];
      final appToken = appInfo is Map ? _nonempty(appInfo['app_token']) : null;
      if (appToken == null) throw _unsupported;
      final devices = await _jsonRequest(
        client,
        'GET',
        Uri(
          scheme: 'https',
          host: 'api-mifit.zepp.com',
          pathSegments: ['users', userId, 'devices'],
          queryParameters: {
            'r': [_uuid(), _uuid()],
            'enableMultiDeviceOnMultiType': ['true', 'true'],
            'userid': userId,
            'appid': BigInt.parse(
              _uuid().replaceAll('-', '').substring(0, 16),
              radix: 16,
            ).toString(),
            'channel': 'a100900101016',
            'country': 'US',
            'cv': _version,
            'device': 'android_32',
            'device_type': 'android_phone',
            'enableMultiDevice': 'true',
            'lang': 'en_US',
            'timezone': 'Europe/London',
            'v': '2.0',
          },
        ),
        headers: {
          ..._headers,
          'apptoken': appToken,
          'channel': 'a100900101016',
          'country': 'US',
          'lang': 'en_US',
          'timezone': 'Europe/London',
          'x-request-id': _uuid(),
        },
      );
      final key = selectZeppAccountKey(devices, device.address);
      zeppDiagnostic('ACCOUNT_KEY_MATCHED');
      return key;
    } on ZeppException {
      zeppDiagnostic('ACCOUNT_RECOVERY_ERROR');
      rethrow;
    } on TimeoutException {
      zeppDiagnostic('ACCOUNT_RECOVERY_TIMEOUT');
      throw const ZeppException(
        'Zepp non ha risposto in tempo. Riprova quando vuoi.',
      );
    } catch (_) {
      zeppDiagnostic('ACCOUNT_RECOVERY_ERROR');
      // Never surface raw exceptions: URLs/response bodies can contain secrets.
      throw const ZeppException(
        'Recupero non riuscito. Controlla la connessione; puoi usare la chiave manuale.',
      );
    } finally {
      // Dropping local credentials is not a server logout. Mobile/explicit
      // logout can invalidate Zepp's existing session, so neither is used.
      client.close();
    }
  }

  static Map<String, String> get _webHeaders => {
    'app_name': _webApp,
    'appname': _webApp,
    'appplatform': 'web',
    'Origin': 'https://user.zepp.com',
    'Referer': 'https://user.zepp.com/',
    'User-Agent': _webAgent,
    'Content-Type': _contentType,
    'x-request-id': _uuid(),
  };

  static Map<String, String> get _headers => {
    'appname': 'com.huami.midong',
    'cv': _version,
    'v': '2.0',
    'appplatform': 'android_phone',
    'vb': '202509151347',
    'vn': '9.12.5',
    'User-Agent': _agent,
    'hm-privacy-diagnostics': 'false',
    'hm-privacy-ceip': 'false',
  };

  Future<http.Response> _request(
    http.Client client,
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return (() async {
      final response = await client.send(request);
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 1024 * 1024) throw _unsupported;
        bytes.addAll(chunk);
      }
      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      );
    })().timeout(
      requestTimeout,
      onTimeout: () {
        client.close();
        throw TimeoutException('Zepp request deadline');
      },
    );
  }

  Future<Map<String, dynamic>> _jsonRequest(
    http.Client client,
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final response = await _request(
      client,
      method,
      uri,
      headers: headers,
      body: body,
    );
    if (response.statusCode == 429) throw _rateLimited;
    if (response.statusCode != 200) throw _unsupported;
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) throw _unsupported;
    return json;
  }
}

const _unsupported = ZeppException(
  'La risposta Zepp non è compatibile con il recupero. Puoi usare la chiave manuale.',
);
const _rateLimited = ZeppException(
  'Troppi accessi a Zepp. Attendi prima di riprovare.',
);

String? _nonempty(dynamic value) => value is String && value.isNotEmpty
    ? value
    : value is int
    ? '$value'
    : null;

String? _mac(String value) {
  final compact = value.replaceAll(RegExp('[:-]'), '').toUpperCase();
  return RegExp(r'^[0-9A-F]{12}$').hasMatch(compact) ? compact : null;
}

/// Match the selected bonded device by full address, never by display name or
/// list position. btKey is deliberately not assumed to be a music auth_key.
String selectZeppAccountKey(Map<String, dynamic> response, String address) {
  final target = _mac(address);
  if (target == null) throw _unsupported;
  final items = response['items'];
  if (items is! List) throw _unsupported;
  final matches = items
      .whereType<Map<String, dynamic>>()
      .where(
        (item) =>
            item['macAddress'] is String && _mac(item['macAddress']) == target,
      )
      .toList();
  if (matches.length != 1) {
    throw const ZeppException(
      'Questo orologio non è identificabile in modo univoco nell’account. '
      'Controlla di usare lo stesso account di Zepp.',
    );
  }
  dynamic info = matches.single['additionalInfo'];
  if (info is String) {
    try {
      info = jsonDecode(info);
    } catch (_) {
      throw _unsupported;
    }
  }
  final key = info is Map ? info['auth_key'] : null;
  if (key is! String || !isValidZeppKey(key)) {
    throw const ZeppException(
      'Zepp non restituisce una chiave compatibile per questo orologio. '
      'Sincronizzalo in Zepp oppure usa la chiave manuale.',
    );
  }
  return key.trim().replaceFirst(RegExp(r'^0[xX]'), '').toLowerCase();
}

Uint8List _form(Map<String, dynamic> fields) => Uint8List.fromList(
  utf8.encode(
    fields.entries
        .expand(
          (
            entry,
          ) => (entry.value is List ? entry.value as List : [entry.value]).map(
            (value) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('$value')}',
          ),
        )
        .join('&'),
  ),
);

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
