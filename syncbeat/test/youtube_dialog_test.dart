import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/youtube_match_dialog.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';
import 'package:syncbeat/features/audio_sources/youtube_downloader.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/models/spotify_models.dart';

import 'youtube_test.dart' as fixtures;

class _Tools extends YoutubeTools {
  const _Tools();
  @override
  Future<List<YoutubeVideo>> search(
    SpotifyTrack track,
    DownloadCancellationToken cancellation,
  ) async => [
    fixtures.video('aaaaaaaaaaa'),
    fixtures.video('bbbbbbbbbbb', title: 'Blue Sky live', channel: 'Other'),
  ];
}

class _TiedTools extends YoutubeTools {
  const _TiedTools();
  @override
  Future<List<YoutubeVideo>> search(
    SpotifyTrack track,
    DownloadCancellationToken cancellation,
  ) async => [
    for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb'])
      YoutubeVideo({
        ...fixtures.video(id).metadata,
        'channel_id': 'UCaaaaaaaaaaaaaaaaaaaaaa',
        'channel_is_verified': true,
      }),
  ];
}

class _UnusedStorage implements AudioStagingStorage {
  @override
  Future<StagedAudioFile?> findExistingCandidate(
    AudioCandidate candidate,
  ) async => null;
  @override
  Future<StagedAudioFile> saveMp3({
    required AudioCandidate candidate,
    required Stream<List<int>> bytes,
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
    int? expectedBytes,
  }) => throw UnimplementedError();
}

class _Download extends YoutubeDownloader {
  _Download() : super(tools: const _Tools(), storage: _UnusedStorage());
  int calls = 0;
  bool fail = false;
  @override
  Future<StagedAudioFile> download({
    required SpotifyTrack track,
    required YoutubeVideo video,
    required YoutubeDownloadAuthorization authorization,
    required DownloadCancellationToken cancellation,
    required AudioDownloadProgress onProgress,
    void Function(String phase)? onPhase,
  }) async {
    expect(authorization.valid, isTrue);
    calls++;
    if (fail) throw const AudioSourceException('Errore di prova del download.');
    onPhase?.call('Conversione MP3');
    return StagedAudioFile(
      path: 'content://media/external/downloads/42',
      fileName: 'tone.mp3',
      sizeBytes: 500,
      sha256: 'test',
      candidate: const AudioCandidate(
        id: 'tone',
        providerId: 'youtube',
        title: 'Tone',
        artist: 'Own test',
        durationSeconds: 1,
        license: AudioLicense(name: 'Own audio'),
      ),
      stagedAt: DateTime(2026),
    );
  }
}

void main() {
  testWidgets(
    'download footer is visible and requires saved choice plus both permissions; authorised click starts download',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final download = _Download();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => YoutubeMatchDialog(
                    track: fixtures.track,
                    tools: const _Tools(),
                    downloader: download,
                  ),
                ),
                child: const Text('Apri'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerca su YouTube'));
      await tester.pumpAndSettle();
      expect(find.text('Scarica MP3'), findsNothing);
      await tester.ensureVisible(find.text('Blue Sky live'));
      await tester.tap(find.text('Blue Sky live'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Scarica MP3');
      expect(tester.getRect(button).bottom, lessThan(852));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.byType(TextField), findsNothing);
      for (var index = 0; index < 2; index++) {
        final target = find.byType(CheckboxListTile).at(index);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<FilledButton>(button).onPressed,
        isNull,
        reason:
            'Authorisation does not replace explicit association confirmation',
      );
      final save = find.text('Salva associazione Spotify → YouTube');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(download.calls, 1);
      expect(find.text('Apri file'), findsOneWidget);
      expect(find.text('Apri cartella'), findsOneWidget);
      expect(
        find.textContaining('MP3 salvato in Download/SyncBeat'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      download.fail = true;
      await tester.tap(button);
      await tester.pumpAndSettle();
      final error = find.text('Errore di prova del download.');
      expect(error, findsOneWidget);
      expect(tester.getRect(error).top, greaterThan(0));
      expect(tester.getRect(error).bottom, lessThan(852));
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'YouTube dialog stays usable on 320px phone with text scale $scale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const YoutubeMatchDialog(
                      track: fixtures.track,
                      tools: _Tools(),
                    ),
                  ),
                  child: const Text('Apri'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Apri'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cerca su YouTube'));
        await tester.tap(find.text('Cerca su YouTube'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Blue Sky live'));
        await tester.tap(find.text('Blue Sky live'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text('Salva associazione Spotify → YouTube'),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Salva associazione Spotify → YouTube'));
        await tester.pumpAndSettle();
        expect(
          (await YoutubeAssociations().read(fixtures.track.id))!.id,
          'bbbbbbbbbbb',
        );
      },
    );
  }
  testWidgets(
    'shows ambiguity, channel links, reasons and verification without claiming OAC',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: YoutubeMatchDialog(
              track: fixtures.track,
              tools: _TiedTools(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerca su YouTube'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Risultato ambiguo'), findsOneWidget);
      expect(find.text('Canale verificato'), findsNWidgets(2));
      expect(find.text('Stato OAC sconosciuto'), findsNWidgets(2));
      expect(find.text('Apri canale'), findsNWidgets(2));
      expect(find.textContaining('Differenza durata +0.0 s'), findsNWidgets(2));
      expect(find.textContaining('Artista ufficiale'), findsNothing);
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        isNull,
      );
    },
  );
  testWidgets(
    'highlights best without selecting; manually saves a different video',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: YoutubeMatchDialog(track: fixtures.track, tools: _Tools()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerca su YouTube'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Miglior candidato'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        isNull,
      );
      expect(find.text('Salva associazione Spotify → YouTube'), findsNothing);
      await tester.ensureVisible(find.text('Blue Sky live'));
      await tester.tap(find.text('Blue Sky live'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Salva associazione Spotify → YouTube'),
      );
      await tester.tap(find.text('Salva associazione Spotify → YouTube'));
      await tester.pumpAndSettle();
      expect(
        (await YoutubeAssociations().read(fixtures.track.id))!.id,
        'bbbbbbbbbbb',
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Scarica MP3'),
      );
      expect(button.onPressed, isNull);
    },
  );
}
