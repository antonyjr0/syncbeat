import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbeat/app.dart';
import 'package:syncbeat/models/spotify_models.dart';
import 'package:syncbeat/services/metadata_cache.dart';
import 'package:syncbeat/services/spotify_api_service.dart';
import 'package:syncbeat/services/spotify_auth_service.dart';

class _Tokens implements SpotifyTokenStore {
  _Tokens(this.connected);
  final bool connected;
  @override
  Future<void> clear() async {}
  @override
  Future<SpotifyTokens?> read() async => connected
      ? SpotifyTokens(
          accessToken: 'test',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scopes: const {},
        )
      : null;
  @override
  Future<void> write(SpotifyTokens tokens) async {}
}

class _Metadata implements MetadataStore {
  @override
  Future<List<SpotifyPlaylist>> readPlaylists() async => [
    const SpotifyPlaylist(
      id: 'playlist',
      name: 'Una playlist con un nome particolarmente lungo per smartphone',
      owner: 'Test',
      trackCount: 1,
    ),
  ];
  @override
  Future<String?> readSelectedPlaylistId() async => 'playlist';
  @override
  Future<List<SpotifyTrack>> readTracks() async => [
    const SpotifyTrack(
      id: 'track',
      title: 'Titolo del brano molto lungo da visualizzare sul telefono',
      artists: ['Artista principale', 'Artista ospite'],
      album: 'Album con un nome lungo',
      durationMs: 199000,
      isLocal: false,
    ),
  ];
  @override
  Future<void> writePlaylists(List<SpotifyPlaylist> playlists) async {}
  @override
  Future<void> writeSelectedPlaylistId(String? playlistId) async {}
  @override
  Future<void> writeTracks(List<SpotifyTrack> tracks) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [
    const Size(320, 740),
    const Size(393, 852),
    const Size(600, 900),
    const Size(900, 480),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'connected layout ${size.width}x${size.height}, text $scale keeps account and actions readable',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final auth = SpotifyAuthService(secureTokenStore: _Tokens(true));
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(useMaterial3: true),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: SyncBeatHomePage(
                  authService: auth,
                  apiService: SpotifyApiService(
                    tokenService: auth,
                    httpClient: MockClient(
                      (_) async =>
                          http.Response('{"items":[],"next":null}', 200),
                    ),
                  ),
                  metadataStore: _Metadata(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final account = find.byKey(const ValueKey('spotify-account-title'));
          final paragraph = tester.renderObject<RenderParagraph>(account);
          expect(
            paragraph.size.width,
            greaterThan(160),
            reason: 'Account text must not be squeezed into a few characters',
          );
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout(maxWidth: paragraph.size.width);
          expect(painter.computeLineMetrics().length, lessThanOrEqualTo(2));
          final update = find.widgetWithText(OutlinedButton, 'Aggiorna');
          painter.dispose();
          if (tester
                      .getSize(
                        find.byKey(const ValueKey('spotify-connection-panel')),
                      )
                      .width /
                  scale <
              650) {
            expect(
              tester.getTopLeft(update).dy,
              greaterThan(tester.getBottomLeft(account).dy),
              reason:
                  'Actions must move below account details on narrow screens',
            );
          } else {
            expect(
              (tester.getTopLeft(update).dy - tester.getTopLeft(account).dy)
                  .abs(),
              lessThan(60),
            );
          }
          await tester.scrollUntilVisible(
            find.text('Carica brani'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text(
              'Titolo del brano molto lungo da visualizzare sul telefono',
            ),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          expect(
            find.byTooltip('Cerca una fonte audio autorizzata'),
            findsOneWidget,
          );
          if (size.width == 393 && scale == 1) {
            await tester.ensureVisible(find.text('YouTube / MP3'));
            await tester.tap(find.text('YouTube / MP3'));
            await tester.pumpAndSettle();
            expect(find.text('Cerca su YouTube'), findsOneWidget);
            expect(
              find.text('Scarica MP3'),
              findsNothing,
              reason: 'A video must be selected manually first',
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets('signed-out phone layout keeps login available', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = SpotifyAuthService(secureTokenStore: _Tokens(false));
    await tester.pumpWidget(
      MaterialApp(
        home: SyncBeatHomePage(authService: auth, metadataStore: _Metadata()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Collega account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
