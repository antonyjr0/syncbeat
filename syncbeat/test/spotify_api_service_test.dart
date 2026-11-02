import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbeat/services/spotify_api_service.dart';
import 'package:syncbeat/services/spotify_auth_service.dart';

void main() {
  group('SpotifyApiService', () {
    test('loads all playlist pages in order', () async {
      final auth = _authService();
      final client = MockClient((request) async {
        if (request.url.queryParameters['offset'] == '0') {
          return http.Response(
            jsonEncode({
              'items': [_playlist('first', 'First')],
              'next':
                  'https://api.spotify.com/v1/me/playlists?offset=50&limit=50',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [_playlist('second', 'Second')],
            'next': null,
          }),
          200,
        );
      });
      final service = SpotifyApiService(tokenService: auth, httpClient: client);

      final playlists = await service.getCurrentUserPlaylists();

      expect(playlists.map((playlist) => playlist.id), ['first', 'second']);
    });

    test(
      'imports IDs in order and reports unavailable items individually',
      () async {
        final auth = _authService();
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/available')) {
            return http.Response(
              jsonEncode({
                'id': 'available',
                'name': 'Song',
                'artists': [
                  {'name': 'Artist'},
                ],
                'album': {'name': 'Album'},
                'duration_ms': 123000,
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        });
        final service = SpotifyApiService(
          tokenService: auth,
          httpClient: client,
        );

        final results = await service.importTrackIds(['available', 'missing']);

        expect(results.map((result) => result.trackId), [
          'available',
          'missing',
        ]);
        expect(results.first.track?.artistLine, 'Artist');
        expect(results.last.track, isNull);
        expect(results.last.error, contains('404'));
      },
    );

    test('retries 429 responses using Retry-After', () async {
      final auth = _authService();
      final delays = <Duration>[];
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          return http.Response('{}', 429, headers: {'retry-after': '4'});
        }
        return http.Response(jsonEncode({'items': [], 'next': null}), 200);
      });
      final service = SpotifyApiService(
        tokenService: auth,
        httpClient: client,
        retryDelay: (duration) async => delays.add(duration),
      );

      await service.getCurrentUserPlaylists();

      expect(attempts, 2);
      expect(delays, [const Duration(seconds: 4)]);
    });
  });
}

SpotifyAuthService _authService() => SpotifyAuthService(
  secureTokenStore: _MemoryTokenStore(
    SpotifyTokens(
      accessToken: 'test-token',
      refreshToken: null,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      scopes: const {},
    ),
  ),
);

Map<String, Object?> _playlist(String id, String name) => {
  'id': id,
  'name': name,
  'owner': {'display_name': 'Owner'},
  'tracks': {'total': 1},
};

class _MemoryTokenStore implements SpotifyTokenStore {
  _MemoryTokenStore(this.tokens);

  SpotifyTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<SpotifyTokens?> read() async => tokens;

  @override
  Future<void> write(SpotifyTokens value) async => tokens = value;
}
