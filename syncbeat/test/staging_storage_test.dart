import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/models/spotify_models.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDirectoryStagingStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'syncbeat-stage-',
    );
    storage = AppDirectoryStagingStorage(
      applicationDirectory: temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('writes a signed MP3 into staging with progress and SHA-256', () async {
    final progress = <DownloadProgress>[];
    final staged = await storage.saveMp3(
      candidate: _candidate().forSpotifyTrack(_spotifyTrack),
      bytes: Stream.value([0x49, 0x44, 0x33, 1, 2, 3]),
      onProgress: progress.add,
      cancellationToken: DownloadCancellationToken(),
      expectedBytes: 6,
    );

    expect(
      staged.path,
      startsWith(
        '${temporaryDirectory.path}${Platform.pathSeparator}audio_staging',
      ),
    );
    expect(staged.fileName, endsWith('.mp3'));
    expect(staged.fileName, isNot(contains('/')));
    expect(staged.sizeBytes, 6);
    expect(staged.sha256, isNotEmpty);
    expect(progress.last.receivedBytes, 6);
    expect(await File(staged.path).exists(), isTrue);
    final manifest =
        jsonDecode(await File('${staged.path}.json').readAsString())
            as Map<String, dynamic>;
    expect(manifest['sha256'], staged.sha256);
    expect(manifest['sourceUrl'], 'https://www.jamendo.com/track/1');
    expect(manifest['spotifyTrack']['id'], 'spotify-test-id');
    expect(manifest['license']['name'], 'CC BY 4.0');
    expect(manifest['providerItemId'], isNot(contains('item/../unsafe')));
  });

  test('removes partial files when cancelled', () async {
    final cancellation = DownloadCancellationToken();
    final storageDirectory = await storage.directory;
    final failed = storage.saveMp3(
      candidate: _candidate(),
      bytes: Stream.fromIterable([
        [0x49, 0x44, 0x33, 1, 2, 3],
        [4, 5, 6],
      ]),
      onProgress: (_) => cancellation.cancel(),
      cancellationToken: cancellation,
    );

    await expectLater(failed, throwsA(isA<DownloadCancelledException>()));
    expect(await storageDirectory.list().toList(), isEmpty);
  });

  test('rejects non-MP3 data and removes the partial file', () async {
    final storageDirectory = await storage.directory;

    await expectLater(
      storage.saveMp3(
        candidate: _candidate(),
        bytes: Stream.value([0, 1, 2, 3, 4]),
        onProgress: (_) {},
        cancellationToken: DownloadCancellationToken(),
      ),
      throwsA(isA<AudioSourceException>()),
    );
    expect(await storageDirectory.list().toList(), isEmpty);
  });

  test('sanitizes hostile filename characters', () {
    final name = AppDirectoryStagingStorage.sanitizeFileName('../a:b?c*');
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains(':')));
    expect(name, isNot(contains('?')));
    expect(name, isNot(contains('*')));
  });
}

AudioCandidate _candidate() => AudioCandidate(
  id: 'item/../unsafe',
  providerId: 'local',
  title: 'Track: title',
  artist: 'Artist? Name',
  durationSeconds: 30,
  license: AudioLicense(
    name: 'CC BY 4.0',
    url: Uri(
      scheme: 'https',
      host: 'creativecommons.org',
      path: '/licenses/by/4.0/',
    ),
    attribution: 'Artist · Jamendo',
    verified: true,
    downloadPermission: true,
    offlineUsePermission: true,
  ),
  isLocalFile: true,
  sourceUrl: Uri(scheme: 'https', host: 'www.jamendo.com', path: '/track/1'),
);

const _spotifyTrack = SpotifyTrack(
  id: 'spotify-test-id',
  title: 'Track title',
  artists: ['Artist name'],
  album: 'Album',
  durationMs: 30000,
  isLocal: false,
);
