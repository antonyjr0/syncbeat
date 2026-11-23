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
import 'package:syncbeat/features/zepp/zepp_download_transfer.dart';
import 'package:syncbeat/features/zepp/zepp_client.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';

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

  testWidgets(
    'download alone never sends; the button sends the actual saved file',
    (tester) async {
      final completed = _CompletedDownload();
      final watch = _WatchTransfer();
      final services = _services(
        temporaryDirectory,
        [_jamendoTrack()],
        offlineUseAuthorized: true,
        downloader: completed,
        watchTransfer: watch,
      );
      await tester.pumpWidget(_app(services));
      await tester.tap(find.text('Apri ricerca audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerca su Jamendo'));
      await tester.pumpAndSettle();
      expect(find.text('Invia all’orologio'), findsNothing);
      final download = find.text('Scarica MP3');
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(watch.files, isEmpty);
      final send = find.text('Invia all’orologio');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(watch.files.single.path, '/actual/staging/returned-2.mp3');
      expect(watch.files.single.name, 'Returned title-2.mp3');
      expect(find.text('Invia all’orologio'), findsOneWidget);
      completed.fail = true;
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(find.text('Invia all’orologio'), findsNothing);
      expect(watch.files, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
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
              watchTransfer: services.watchTransfer,
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
  List<Map<String, dynamic>> tracks, {
  bool offlineUseAuthorized = false,
  AudioSourceDownloader? downloader,
  ZeppDownloadTransfer? watchTransfer,
}) {
  final storage = AppDirectoryStagingStorage(applicationDirectory: directory);
  final jamendo = JamendoProvider(
    clientId: 'test-client-id',
    offlineUseAuthorized: offlineUseAuthorized,
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
      downloader ??
          JamendoAudioDownloader(
            stagingStorage: storage,
            offlineUseAuthorized: false,
          ),
      local,
    ]),
    watchTransfer,
  );
}

class _CompletedDownload implements AudioSourceDownloader {
  bool fail = false;
  @override
  String get id => 'jamendo';
  @override
  bool canDownload(AudioCandidate candidate) => candidate.isAuthorizedDownload;
  @override
  Future<StagedAudioFile> download(
    AudioCandidate candidate, {
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
  }) async {
    if (fail) throw const AudioSourceException('Download non riuscito');
    return StagedAudioFile(
      path: '/actual/staging/returned-2.mp3',
      fileName: 'Returned title-2.mp3',
      sizeBytes: 500,
      sha256: 'test',
      candidate: candidate,
      stagedAt: DateTime(2026),
    );
  }
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
  const _AudioServices(
    this.jamendo,
    this.local,
    this.downloads,
    this.watchTransfer,
  );

  final JamendoProvider jamendo;
  final LocalMp3Provider local;
  final AudioDownloadManager downloads;
  final ZeppDownloadTransfer? watchTransfer;
}

class _WatchTransfer extends ZeppDownloadTransfer {
  final files = <PublishedAudio>[];
  @override
  Future<void> send(
    PublishedAudio file, {
    required String title,
    required String artist,
    required void Function(ZeppEvent) onEvent,
  }) async {
    files.add(file);
    onEvent(const ZeppEvent.status('Invio completato'));
  }
}

class _NoTagsReader implements LocalMp3TagReader {
  @override
  Future<LocalAudioMetadata?> read(LocalMp3File file) async => null;
}
