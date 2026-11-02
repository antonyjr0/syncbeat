import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/jamendo_downloader.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'syncbeat-jamendo-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('downloads an authorized MP3 and reports progress', () async {
    final progress = <DownloadProgress>[];
    final downloader = JamendoAudioDownloader(
      stagingStorage: AppDirectoryStagingStorage(
        applicationDirectory: temporaryDirectory,
      ),
      offlineUseAuthorized: true,
      httpClient: MockClient((request) async {
        expect(request.url.host, 'prod-1.storage.jamendo.com');
        return http.Response.bytes(
          [0x49, 0x44, 0x33, 1, 2, 3],
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      }),
    );

    final staged = await downloader.download(
      _candidate(),
      onProgress: progress.add,
      cancellationToken: DownloadCancellationToken(),
    );

    expect(staged.fileName, endsWith('.mp3'));
    expect(staged.sizeBytes, 6);
    expect(progress, isNotEmpty);
  });

  test('retries a transient HTTP 503 before completing the download', () async {
    final delays = <Duration>[];
    var requests = 0;
    final downloader = JamendoAudioDownloader(
      stagingStorage: AppDirectoryStagingStorage(
        applicationDirectory: temporaryDirectory,
      ),
      offlineUseAuthorized: true,
      retryDelay: (duration) async => delays.add(duration),
      httpClient: MockClient((_) async {
        requests++;
        if (requests == 1) return http.Response('', 503);
        return http.Response.bytes([0x49, 0x44, 0x33, 1, 2, 3], 200);
      }),
    );

    final staged = await downloader.download(
      _candidate(),
      onProgress: (_) {},
      cancellationToken: DownloadCancellationToken(),
    );

    expect(requests, 2);
    expect(delays, [const Duration(seconds: 1)]);
    expect(await File(staged.path).exists(), isTrue);
  });

  test('refuses downloads unless offline authorization is enabled', () async {
    final downloader = JamendoAudioDownloader(
      stagingStorage: AppDirectoryStagingStorage(
        applicationDirectory: temporaryDirectory,
      ),
      offlineUseAuthorized: false,
      httpClient: MockClient((_) async => http.Response('', 200)),
    );

    expect(downloader.canDownload(_candidate()), isFalse);
    await expectLater(
      downloader.download(
        _candidate(),
        onProgress: (_) {},
        cancellationToken: DownloadCancellationToken(),
      ),
      throwsA(isA<AudioSourceException>()),
    );
  });

  test(
    'reuses an existing manifest instead of downloading the same item again',
    () async {
      var requests = 0;
      final downloader = JamendoAudioDownloader(
        stagingStorage: AppDirectoryStagingStorage(
          applicationDirectory: temporaryDirectory,
        ),
        offlineUseAuthorized: true,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response.bytes([0x49, 0x44, 0x33, 1, 2, 3], 200);
        }),
      );

      final first = await downloader.download(
        _candidate(),
        onProgress: (_) {},
        cancellationToken: DownloadCancellationToken(),
      );
      final duplicate = await downloader.download(
        _candidate(),
        onProgress: (_) {},
        cancellationToken: DownloadCancellationToken(),
      );

      expect(requests, 1);
      expect(duplicate.path, first.path);
      expect(await Directory(temporaryDirectory.path).list().length, 1);
    },
  );

  test(
    'cancellation during streaming removes MP3 and manifest files',
    () async {
      final cancellation = DownloadCancellationToken();
      final downloader = JamendoAudioDownloader(
        stagingStorage: AppDirectoryStagingStorage(
          applicationDirectory: temporaryDirectory,
        ),
        offlineUseAuthorized: true,
        httpClient: MockClient(
          (_) async => http.Response.bytes([0x49, 0x44, 0x33, 1, 2, 3], 200),
        ),
      );

      await expectLater(
        downloader.download(
          _candidate(),
          onProgress: (_) => cancellation.cancel(),
          cancellationToken: cancellation,
        ),
        throwsA(isA<DownloadCancelledException>()),
      );
      expect(
        await Directory(
          '${temporaryDirectory.path}/audio_staging',
        ).list().toList(),
        isEmpty,
      );
    },
  );

  test('rejects redirects outside Jamendo download hosts', () async {
    final downloader = JamendoAudioDownloader(
      stagingStorage: AppDirectoryStagingStorage(
        applicationDirectory: temporaryDirectory,
      ),
      offlineUseAuthorized: true,
      httpClient: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://not-jamendo.example/file.mp3'},
        ),
      ),
    );

    await expectLater(
      downloader.download(
        _candidate(),
        onProgress: (_) {},
        cancellationToken: DownloadCancellationToken(),
      ),
      throwsA(isA<AudioSourceException>()),
    );
  });
}

AudioCandidate _candidate() => AudioCandidate(
  id: '123',
  providerId: 'jamendo',
  title: 'Northern Lights',
  artist: 'Elena Sol',
  durationSeconds: 180,
  license: AudioLicense(
    name: 'CC BY 4.0',
    verified: true,
    downloadPermission: true,
    offlineUsePermission: true,
  ),
  downloadUrl: Uri.parse('https://prod-1.storage.jamendo.com/track.mp3'),
  apiAllowsDownload: true,
);
