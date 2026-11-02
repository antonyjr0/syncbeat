import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/jamendo_provider.dart';
import 'package:syncbeat/models/spotify_models.dart';

void main() {
  test(
    'uses the official tracks API and searches by title, artist and duration',
    () async {
      late Uri requestUri;
      final provider = JamendoProvider(
        clientId: 'public-test-client-id',
        httpClient: MockClient((request) async {
          requestUri = request.url;
          return http.Response(_response([_jamendoTrack()]), 200);
        }),
      );

      await provider.search(_spotifyTrack());

      expect(requestUri.host, 'api.jamendo.com');
      expect(requestUri.path, '/v3.0/tracks/');
      expect(requestUri.queryParameters['namesearch'], 'Northern Lights');
      expect(requestUri.queryParameters['artist_name'], 'Elena Sol');
      expect(requestUri.queryParameters['durationbetween'], '165_195');
      expect(requestUri.queryParameters['include'], 'licenses');
    },
  );

  test(
    'requires download permission, recognized license and offline authorization',
    () async {
      final provider = JamendoProvider(
        clientId: 'client',
        offlineUseAuthorized: true,
        httpClient: MockClient(
          (_) async => http.Response(_response([_jamendoTrack()]), 200),
        ),
      );

      final candidate = (await provider.search(_spotifyTrack())).single;

      expect(candidate.apiAllowsDownload, isTrue);
      expect(candidate.license.verified, isTrue);
      expect(candidate.license.downloadPermission, isTrue);
      expect(candidate.license.offlineUsePermission, isTrue);
      expect(candidate.isAuthorizedDownload, isTrue);
      expect(candidate.estimatedSizeBytes, 181 * 24000);
      expect(candidate.license.attribution, contains('Jamendo'));
    },
  );

  test('does not expose a URL when Jamendo denies download', () async {
    final provider = JamendoProvider(
      clientId: 'client',
      offlineUseAuthorized: true,
      httpClient: MockClient(
        (_) async => http.Response(
          _response([_jamendoTrack(allowed: false, download: '')]),
          200,
        ),
      ),
    );

    final candidate = (await provider.search(_spotifyTrack())).single;

    expect(candidate.apiAllowsDownload, isFalse);
    expect(candidate.downloadUrl, isNull);
    expect(candidate.canStage, isFalse);
  });

  test(
    'fails closed for unsupported licenses and offline use by default',
    () async {
      final provider = JamendoProvider(
        clientId: 'client',
        httpClient: MockClient(
          (_) async => http.Response(
            _response([_jamendoTrack(license: 'https://example.com/license')]),
            200,
          ),
        ),
      );

      final candidate = (await provider.search(_spotifyTrack())).single;

      expect(candidate.license.verified, isFalse);
      expect(candidate.isAuthorizedDownload, isFalse);
      expect(candidate.license.restrictionReason, isNotNull);
    },
  );

  test('requires a Jamendo client ID', () async {
    final provider = JamendoProvider(clientId: '');

    await expectLater(
      provider.search(_spotifyTrack()),
      throwsA(isA<AudioSourceException>()),
    );
  });
}

SpotifyTrack _spotifyTrack() => const SpotifyTrack(
  id: 'spotify-1',
  title: 'Northern Lights',
  artists: ['Elena Sol'],
  album: 'Skyline',
  durationMs: 180000,
  isLocal: false,
);

Map<String, dynamic> _jamendoTrack({
  bool allowed = true,
  String download = 'https://prod-1.storage.jamendo.com/download/track/1/mp32/',
  String license = 'https://creativecommons.org/licenses/by/4.0/',
}) => {
  'id': '123',
  'name': 'Northern Lights',
  'artist_name': 'Elena Sol',
  'duration': 181,
  'license_ccurl': license,
  'audiodownload_allowed': allowed,
  'audiodownload': download,
  'shareurl': 'https://www.jamendo.com/track/123',
};

String _response(List<Map<String, dynamic>> results) => jsonEncode({
  'headers': {'status': 'success', 'code': 0, 'results_count': results.length},
  'results': results,
});
