// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:syncbeat/app.dart';
import 'package:syncbeat/models/spotify_models.dart';
import 'package:syncbeat/services/metadata_cache.dart';
import 'package:syncbeat/services/spotify_api_service.dart';
import 'package:syncbeat/services/spotify_auth_service.dart';

void main() {
  testWidgets('shows setup state and Spotify import controls', (tester) async {
    final auth = SpotifyAuthService(secureTokenStore: _MemoryTokenStore());
    final app = SyncBeatApp(
      authService: auth,
      apiService: SpotifyApiService(
        tokenService: auth,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      metadataStore: _MemoryMetadataStore(),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('SyncBeat'), findsOneWidget);
    expect(find.text('Collega account'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Importa i 16 ID test'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Importa i 16 ID test'), findsOneWidget);
    expect(find.text('Database Appwrite'), findsOneWidget);
  });
}

class _MemoryTokenStore implements SpotifyTokenStore {
  SpotifyTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<SpotifyTokens?> read() async => tokens;

  @override
  Future<void> write(SpotifyTokens value) async => tokens = value;
}

class _MemoryMetadataStore implements MetadataStore {
  @override
  Future<List<SpotifyPlaylist>> readPlaylists() async => [];

  @override
  Future<String?> readSelectedPlaylistId() async => null;

  @override
  Future<List<SpotifyTrack>> readTracks() async => [];

  @override
  Future<void> writePlaylists(List<SpotifyPlaylist> playlists) async {}

  @override
  Future<void> writeSelectedPlaylistId(String? playlistId) async {}

  @override
  Future<void> writeTracks(List<SpotifyTrack> tracks) async {}
}
