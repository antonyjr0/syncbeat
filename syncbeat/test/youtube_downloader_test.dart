import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/features/audio_sources/youtube_downloader.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';

import 'youtube_test.dart' as fixtures;

class _Tools extends YoutubeTools {
  _Tools({this.fail = false, this.cancel = false});
  final bool fail;
  final bool cancel;
  String? temporaryPath;
  List<String>? arguments;
  int calls = 0;
  @override
  Future<void> run(
    List<String> arguments, {
    required DownloadCancellationToken cancellation,
    required ToolOutput onLine,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    calls++;
    this.arguments = arguments;
    final output = arguments[arguments.indexOf('--output') + 1].replaceAll(
      '%(ext)s',
      'mp3',
    );
    temporaryPath = File(output).parent.path;
    await File(output).writeAsBytes([0x49, 0x44, 0x33, ...List.filled(100, 0)]);
    if (cancel) cancellation.cancel();
    if (fail) throw const AudioSourceException('Conversion failed');
  }
}

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'youtube-download-test-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));
  const authorization = YoutubeDownloadAuthorization(
    evidence: 'Permesso scritto proprietario e piattaforma, riferimento 123',
    rightsAndPlatformPermission: true,
    conversionAndOfflineUse: true,
  );

  test(
    'uses the supplied app cache and cleans only its own temporary child',
    () async {
      final cache = await Directory('${directory.path}/private-cache').create();
      final sentinel = await File(
        '${cache.path}/keep.txt',
      ).writeAsString('keep');
      final tools = _Tools();
      await YoutubeDownloader(
        tools: tools,
        temporaryDirectory: cache,
        storage: AppDirectoryStagingStorage(applicationDirectory: directory),
      ).download(
        track: fixtures.track,
        video: fixtures.video('aaaaaaaaaaa'),
        authorization: authorization,
        cancellation: DownloadCancellationToken(),
        onProgress: (_) {},
      );
      expect(
        tools.temporaryPath,
        startsWith('${cache.path}${Platform.pathSeparator}'),
      );
      expect(await Directory(tools.temporaryPath!).exists(), isFalse);
      expect(await sentinel.readAsString(), 'keep');
    },
  );

  test(
    'authorized MP3 is staged with manifest, hash and progress; private temporary output is removed',
    () async {
      final tools = _Tools();
      final progress = <DownloadProgress>[];
      final file =
          await YoutubeDownloader(
            tools: tools,
            storage: AppDirectoryStagingStorage(
              applicationDirectory: directory,
            ),
          ).download(
            track: fixtures.track,
            video: fixtures.video('aaaaaaaaaaa'),
            authorization: authorization,
            cancellation: DownloadCancellationToken(),
            onProgress: progress.add,
          );
      expect(await File(file.path).exists(), isTrue);
      expect(
        await File('${file.path}.json').readAsString(),
        contains(authorization.evidence),
      );
      expect(file.candidate.spotifyTrackId, fixtures.track.id);
      expect(file.sha256.length, 64);
      expect(progress.last.fraction, 1);
      expect(await Directory(tools.temporaryPath!).exists(), isFalse);
      expect(
        tools.arguments,
        containsAll(['--extract-audio', '--audio-format', 'mp3']),
      );
      final repeated =
          await YoutubeDownloader(
            tools: tools,
            storage: AppDirectoryStagingStorage(
              applicationDirectory: directory,
            ),
          ).download(
            track: fixtures.track,
            video: fixtures.video('aaaaaaaaaaa'),
            authorization: authorization,
            cancellation: DownloadCancellationToken(),
            onProgress: (_) {},
          );
      expect(repeated.path, file.path);
      expect(tools.calls, 1, reason: 'An intact existing download is reused');
    },
  );
  for (final cancel in [false, true]) {
    test(
      '${cancel ? 'cancellation' : 'conversion error'} leaves no staged audio or private partial files',
      () async {
        final tools = _Tools(fail: !cancel, cancel: cancel);
        await expectLater(
          YoutubeDownloader(
            tools: tools,
            storage: AppDirectoryStagingStorage(
              applicationDirectory: directory,
            ),
          ).download(
            track: fixtures.track,
            video: fixtures.video('aaaaaaaaaaa'),
            authorization: authorization,
            cancellation: DownloadCancellationToken(),
            onProgress: (_) {},
          ),
          throwsA(
            cancel
                ? isA<DownloadCancelledException>()
                : isA<AudioSourceException>(),
          ),
        );
        expect(await Directory(tools.temporaryPath!).exists(), isFalse);
        expect(
          await directory
              .list(recursive: true)
              .where((f) => f.path.endsWith('.mp3'))
              .isEmpty,
          isTrue,
        );
      },
    );
  }
}
