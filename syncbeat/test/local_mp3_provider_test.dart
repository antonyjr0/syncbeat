import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/local_mp3_provider.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';

void main() {
  test('requires an explicit user rights confirmation', () async {
    final provider = _provider(files: [_file('Artist - Title.mp3')]);

    await expectLater(
      provider.pickFiles(userConfirmedRights: false),
      throwsA(isA<AudioSourceException>()),
    );
  });

  test('reads ID3 metadata and ignores non-MP3 selections', () async {
    final provider = _provider(
      files: [_file('renamed.mp3', sizeBytes: 4096), _file('cover.jpg')],
      metadata: const LocalAudioMetadata(
        title: 'Northern Lights',
        artist: 'Elena Sol',
        durationSeconds: 180,
        codec: 'MP3',
      ),
    );

    final candidates = await provider.pickFiles(userConfirmedRights: true);

    expect(candidates, hasLength(1));
    expect(candidates.single.title, 'Northern Lights');
    expect(candidates.single.artist, 'Elena Sol');
    expect(candidates.single.durationSeconds, 180);
    expect(candidates.single.estimatedSizeBytes, 4096);
    expect(provider.canDownload(candidates.single), isTrue);
  });

  test(
    'uses artist-title filename as a fallback when tags are absent',
    () async {
      final provider = _provider(
        files: [_file('Elena Sol - Northern Lights.mp3')],
      );

      final candidate = (await provider.pickFiles(
        userConfirmedRights: true,
      )).single;

      expect(candidate.artist, 'Elena Sol');
      expect(candidate.title, 'Northern Lights');
    },
  );
}

LocalMp3Provider _provider({
  required List<LocalMp3File> files,
  LocalAudioMetadata? metadata,
}) => LocalMp3Provider(
  stagingStorage: AppDirectoryStagingStorage(),
  picker: () async => files,
  tagReader: _FakeTagReader(metadata),
);

LocalMp3File _file(String name, {int? sizeBytes}) => LocalMp3File(
  name: name,
  sizeBytes: sizeBytes,
  openRead: () => Stream.value(Uint8List.fromList([0x49, 0x44, 0x33, 1, 2, 3])),
  readBytes: () async => Uint8List.fromList([0x49, 0x44, 0x33, 1, 2, 3]),
);

class _FakeTagReader implements LocalMp3TagReader {
  const _FakeTagReader(this.metadata);

  final LocalAudioMetadata? metadata;

  @override
  Future<LocalAudioMetadata?> read(LocalMp3File file) async => metadata;
}
