import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/spotify_models.dart';
import 'spotify_auth_service.dart';

class SpotifyApiException implements Exception {
  const SpotifyApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

typedef SpotifyRetryDelay = Future<void> Function(Duration duration);

class SpotifyApiService {
  SpotifyApiService({
    required SpotifyAuthService tokenService,
    http.Client? httpClient,
    SpotifyRetryDelay? retryDelay,
  }) : _authService = tokenService,
       _httpClient = httpClient ?? http.Client(),
       _retryDelay = retryDelay ?? _defaultRetryDelay;

  final SpotifyAuthService _authService;
  final http.Client _httpClient;
  final SpotifyRetryDelay _retryDelay;
  static const _apiRoot = 'https://api.spotify.com/v1';

  static Future<void> _defaultRetryDelay(Duration duration) =>
      Future<void>.delayed(duration);

  Future<List<SpotifyPlaylist>> getCurrentUserPlaylists() async {
    var uri = Uri.parse('$_apiRoot/me/playlists?limit=50&offset=0');
    final playlists = <SpotifyPlaylist>[];
    do {
      final payload = await _getJson(uri);
      final items = payload['items'] as List<dynamic>? ?? const [];
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final playlist = SpotifyPlaylist.fromJson(item);
        if (playlist.id.isNotEmpty) playlists.add(playlist);
      }
      final next = payload['next'] as String?;
      uri = next == null ? Uri() : _nextPageUri(next);
    } while (uri.hasScheme);
    return playlists;
  }

  Future<List<SpotifyTrack>> getPlaylistTracks(String playlistId) async {
    var uri = Uri.https('api.spotify.com', '/v1/playlists/$playlistId/items', {
      'limit': '50',
      'offset': '0',
    });
    final tracks = <SpotifyTrack>[];
    do {
      final payload = await _getJson(uri);
      final items = payload['items'] as List<dynamic>? ?? const [];
      for (final entry in items.whereType<Map<String, dynamic>>()) {
        final item = (entry['item'] ?? entry['track']) as Map<String, dynamic>?;
        if (item == null || item['type'] == 'episode') continue;
        final track = SpotifyTrack.fromJson(
          item,
          isLocal: entry['is_local'] as bool? ?? false,
        );
        if (track.id.isNotEmpty) tracks.add(track);
      }
      final next = payload['next'] as String?;
      uri = next == null ? Uri() : _nextPageUri(next);
    } while (uri.hasScheme);
    return tracks;
  }

  Future<List<TrackImportResult>> importTrackIds(
    Iterable<String> trackIds,
  ) async {
    final results = <TrackImportResult>[];
    for (final trackId in trackIds) {
      try {
        final payload = await _getJson(
          Uri.https('api.spotify.com', '/v1/tracks/$trackId'),
        );
        results.add(
          TrackImportResult(
            trackId: trackId,
            track: SpotifyTrack.fromJson(payload),
          ),
        );
      } on SpotifyApiException catch (error) {
        results.add(TrackImportResult(trackId: trackId, error: error.message));
      }
    }
    return results;
  }

  Uri _nextPageUri(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' || uri.host != 'api.spotify.com') {
      throw const SpotifyApiException(
        0,
        'Spotify ha restituito un URL pagina non valido.',
      );
    }
    return uri;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    var refreshedAfterUnauthorized = false;
    var rateLimitRetries = 0;
    while (true) {
      final token = await _authService.validAccessToken();
      if (token == null) {
        throw const SpotifyApiException(
          401,
          'Collega il tuo account Spotify per continuare.',
        );
      }
      final response = await _httpClient
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 && !refreshedAfterUnauthorized) {
        refreshedAfterUnauthorized = true;
        await _authService.refreshAccessToken();
        continue;
      }
      if (response.statusCode == 429 && rateLimitRetries < 3) {
        rateLimitRetries++;
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
        await _retryDelay(Duration(seconds: retryAfter.clamp(1, 120).toInt()));
        continue;
      }
      if (response.statusCode == 403) {
        throw const SpotifyApiException(
          403,
          'Spotify non consente l’accesso a questi contenuti. La playlist potrebbe non essere tua o condivisa con te.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SpotifyApiException(
          response.statusCode,
          'Richiesta Spotify non riuscita (${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const SpotifyApiException(0, 'Risposta Spotify non valida.');
      }
      return decoded;
    }
  }
}
