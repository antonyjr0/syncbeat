import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbeat/features/audio_sources/audio_match_dialog.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/jamendo_downloader.dart';
import 'package:syncbeat/features/audio_sources/jamendo_provider.dart';
import 'package:syncbeat/features/audio_sources/local_mp3_provider.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/models/spotify_models.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'syncbeat-dialog-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'shows license and confidence, and blocks offline download by default',
    (tester) async {
      final services = _services(temporaryDirectory, [_jamendoTrack()]);
      await tester.pumpWidget(_app(services));
      await tester.tap(find.text('Apri ricerca audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerca su Jamendo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fonte: jamendo · 100%'), findsOneWidget);
      expect(find.textContaining('CC BY 4.0'), findsOneWidget);
      expect(
        find.textContaining('escludono l’accesso offline'),
        findsOneWidget,
      );
      final downloadButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Scarica MP3'),
      );
      expect(downloadButton.onPressed, isNull);
    },
  );

  testWidgets('asks for manual selection when Jamendo results are tied', (
    tester,
  ) async {
    final services = _services(temporaryDirectory, [
      _jamendoTrack(id: '1'),
      _jamendoTrack(id: '2'),
    ]);
    await tester.pumpWidget(_app(services));
    await tester.tap(find.text('Apri ricerca audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerca su Jamendo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Selezione manuale richiesta'), findsOneWidget);
    expect(find.byType(RadioListTile<AudioCandidate>), findsNWidgets(2));
  });
}

Widget _app(_AudioServices services) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AudioMatchDialog(
              track: _track(),
              jamendoProvider: services.jamendo,
              localProvider: services.local,
              downloadManager: services.downloads,
            ),
          ),
          child: const Text('Apri ricerca audio'),
        ),
      ),
    ),
  ),
);

_AudioServices _services(
  Directory directory,
  List<Map<String, dynamic>> tracks,
) {
  final storage = AppDirectoryStagingStorage(applicationDirectory: directory);
  final jamendo = JamendoProvider(
    clientId: 'test-client-id',
    httpClient: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'headers': {'status': 'success', 'code': 0},
          'results': tracks,
        }),
        200,
      ),
    ),
  );
  final local = LocalMp3Provider(
    stagingStorage: storage,
    picker: () async => [],
    tagReader: _NoTagsReader(),
  );
  return _AudioServices(
    jamendo,
    local,
    AudioDownloadManager([
      JamendoAudioDownloader(
        stagingStorage: storage,
        offlineUseAuthorized: false,
      ),
      local,
    ]),
  );
}

SpotifyTrack _track() => const SpotifyTrack(
  id: 'spotify-1',
  title: 'Northern Lights',
  artists: ['Elena Sol'],
  album: 'Skyline',
  durationMs: 180000,
  isLocal: false,
);

Map<String, dynamic> _jamendoTrack({String id = '1'}) => {
  'id': id,
  'name': 'Northern Lights',
  'artist_name': 'Elena Sol',
  'duration': 180,
  'license_ccurl': 'https://creativecommons.org/licenses/by/4.0/',
  'audiodownload_allowed': true,
  'audiodownload': 'https://prod-1.storage.jamendo.com/download/$id.mp3',
  'shareurl': 'https://www.jamendo.com/track/$id',
};

class _AudioServices {
  const _AudioServices(this.jamendo, this.local, this.downloads);

  final JamendoProvider jamendo;
  final LocalMp3Provider local;
  final AudioDownloadManager downloads;
}

class _NoTagsReader implements LocalMp3TagReader {
  @override
  Future<LocalAudioMetadata?> read(LocalMp3File file) async => null;
}
