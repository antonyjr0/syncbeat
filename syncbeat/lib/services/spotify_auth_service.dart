import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SpotifyTokens {
  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final Set<String> scopes;

  bool get isExpired =>
      !expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 45)));

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'scopes': scopes.toList(),
  };

  factory SpotifyTokens.fromJson(Map<String, dynamic> json) => SpotifyTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    scopes: (json['scopes'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toSet(),
  );
}

abstract interface class SpotifyTokenStore {
  Future<SpotifyTokens?> read();
  Future<void> write(SpotifyTokens tokens);
  Future<void> clear();
}

class SecureSpotifyTokenStore implements SpotifyTokenStore {
  SecureSpotifyTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'spotify_tokens_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SpotifyTokens?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      return SpotifyTokens.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(SpotifyTokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class SpotifyAuthService {
  SpotifyAuthService({
    required SpotifyTokenStore secureTokenStore,
    String spotifyClientId = AppConfig.spotifyClientId,
    http.Client? httpClient,
    AppLinks? appLinks,
    Future<bool> Function(Uri uri)? openExternal,
    this.callbackTimeout = const Duration(minutes: 3),
  }) : _tokenStore = secureTokenStore,
       _clientId = spotifyClientId,
       _httpClient = httpClient ?? http.Client(),
       _appLinks = appLinks ?? AppLinks(),
       _openExternal = openExternal ?? _launchExternal;

  final SpotifyTokenStore _tokenStore;
  final String _clientId;
  final http.Client _httpClient;
  final AppLinks _appLinks;
  final Future<bool> Function(Uri uri) _openExternal;
  final Duration callbackTimeout;
  bool _signingIn = false;

  static Uri get redirectUri {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return Uri.parse(AppConfig.windowsRedirectUri);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return Uri.parse(AppConfig.androidRedirectUri);
    }
    throw const SpotifyAuthException(
      'L’autenticazione Spotify è configurata solo per Android e Windows.',
    );
  }

  static String createCodeVerifier({Random? random}) {
    final source = random ?? Random.secure();
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      64,
      (_) => characters[source.nextInt(characters.length)],
    ).join();
  }

  static String createCodeChallenge(String verifier) => base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');

  static String createState({Random? random}) {
    final source = random ?? Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => source.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<SpotifyTokens?> get storedTokens => _tokenStore.read();

  Future<String?> validAccessToken() async {
    var tokens = await _tokenStore.read();
    if (tokens == null) return null;
    if (!tokens.isExpired) return tokens.accessToken;
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      await _tokenStore.clear();
      return null;
    }
    tokens = await _refresh(refreshToken, tokens.scopes);
    await _tokenStore.write(tokens);
    return tokens.accessToken;
  }

  Future<String> refreshAccessToken() async {
    final tokens = await _tokenStore.read();
    final refreshToken = tokens?.refreshToken;
    if (tokens == null || refreshToken == null) {
      await _tokenStore.clear();
      throw const SpotifyAuthException('Ricollega il tuo account Spotify.');
    }
    final refreshed = await _refresh(refreshToken, tokens.scopes);
    await _tokenStore.write(refreshed);
    return refreshed.accessToken;
  }

  Future<SpotifyTokens> signIn() async {
    final redirect = redirectUri;
    final verifier = createCodeVerifier();
    final state = createState();
    final authorizeUri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': _clientId,
      'response_type': 'code',
      'redirect_uri': redirect.toString(),
      'scope': AppConfig.spotifyScopes.join(' '),
      'state': state,
      'code_challenge_method': 'S256',
      'code_challenge': createCodeChallenge(verifier),
    });

    if (_signingIn) {
      throw const SpotifyAuthException('Accesso Spotify già in corso.');
    }
    _signingIn = true;
    HttpServer? server;
    StreamSubscription<HttpRequest>? windowsSubscription;
    StreamSubscription<Uri>? androidSubscription;
    final callback = Completer<Uri>();
    // A listener can fail while opening the browser; retain the error for await
    // without allowing it to escape as an unhandled asynchronous exception.
    callback.future.ignore();
    void fail(Object error, StackTrace stack) {
      if (!callback.isCompleted) callback.completeError(error, stack);
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        try {
          server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            redirect.port,
          );
        } on SocketException {
          throw SpotifyAuthException(
            'La porta ${redirect.port} è occupata. Chiudi il processo che la usa e riprova.',
          );
        }
        windowsSubscription = server.listen((request) {
          if (request.uri.path != redirect.path) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.close().ignore();
            return;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(
              '<!doctype html><title>SyncBeat</title><p>Puoi tornare a SyncBeat.</p>',
            );
          request.response.close().ignore();
          if (!callback.isCompleted) callback.complete(request.uri);
        }, onError: fail);
      } else {
        androidSubscription = _appLinks.uriLinkStream.listen((uri) {
          // app_links may replay the launch URI from a previous login. Only the
          // current PKCE transaction can complete this attempt.
          if (uri.scheme == redirect.scheme &&
              uri.host == redirect.host &&
              uri.path == redirect.path &&
              uri.queryParameters['state'] == state &&
              !callback.isCompleted) {
            callback.complete(uri);
          }
        }, onError: fail);
      }
      if (!await _openExternal(authorizeUri).timeout(callbackTimeout)) {
        throw const SpotifyAuthException(
          'Impossibile aprire il browser per autorizzare Spotify.',
        );
      }
      final responseUri = await callback.future.timeout(callbackTimeout);
      final responseState = responseUri.queryParameters['state'];
      if (responseState != state) {
        throw const SpotifyAuthException(
          'Risposta OAuth non valida: il parametro state non corrisponde.',
        );
      }
      final error = responseUri.queryParameters['error'];
      if (error != null) {
        throw SpotifyAuthException(
          'Autorizzazione Spotify annullata o rifiutata: $error.',
        );
      }
      final code = responseUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const SpotifyAuthException(
          'Spotify non ha restituito un authorization code.',
        );
      }

      final tokens = await _exchangeCode(code, verifier, redirect);
      await _tokenStore.write(tokens);
      return tokens;
    } on TimeoutException {
      throw const SpotifyAuthException(
        'Tempo scaduto in attesa del callback Spotify. Verifica il redirect URI registrato.',
      );
    } finally {
      try {
        await server?.close(force: true);
        await windowsSubscription?.cancel();
        await androidSubscription?.cancel();
      } finally {
        _signingIn = false;
      }
    }
  }

  Future<SpotifyTokens> _exchangeCode(
    String code,
    String verifier,
    Uri redirect,
  ) async {
    final response = await _httpClient
        .post(
          Uri.https('accounts.spotify.com', '/api/token'),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': _clientId,
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirect.toString(),
            'code_verifier': verifier,
          },
        )
        .timeout(const Duration(seconds: 20));
    return _parseTokenResponse(response, const {});
  }

  Future<SpotifyTokens> _refresh(
    String refreshToken,
    Set<String> scopes,
  ) async {
    final response = await _httpClient
        .post(
          Uri.https('accounts.spotify.com', '/api/token'),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': _clientId,
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
          },
        )
        .timeout(const Duration(seconds: 20));
    return _parseTokenResponse(
      response,
      scopes,
      fallbackRefreshToken: refreshToken,
    );
  }

  SpotifyTokens _parseTokenResponse(
    http.Response response,
    Set<String> fallbackScopes, {
    String? fallbackRefreshToken,
  }) {
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body is Map
          ? body['error_description'] ?? body['error']
          : null;
      throw SpotifyAuthException(
        'Spotify token endpoint (${response.statusCode}): ${error ?? 'risposta non valida'}.',
      );
    }
    if (body is! Map<String, dynamic> || body['access_token'] is! String) {
      throw const SpotifyAuthException('Risposta token Spotify non valida.');
    }
    final returnedScopes = (body['scope'] as String? ?? '').split(' ')
      ..removeWhere((scope) => scope.isEmpty);
    return SpotifyTokens(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String? ?? fallbackRefreshToken,
      expiresAt: DateTime.now().add(
        Duration(seconds: body['expires_in'] as int? ?? 3600),
      ),
      scopes: returnedScopes.isEmpty ? fallbackScopes : returnedScopes.toSet(),
    );
  }

  Future<void> signOut() => _tokenStore.clear();

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
