import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';

const candidate = AudioCandidate(
  id: 'aaaaaaaaaaa',
  providerId: 'youtube',
  title: 'Synthetic tone',
  artist: 'SyncBeat test',
  durationSeconds: 1,
  license: AudioLicense(
    name: 'Own generated test audio',
    verified: true,
    downloadPermission: true,
    offlineUsePermission: true,
  ),
);

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getDownloadsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PublicAudioStorage storage;
  final fixture = File('test/fixtures/authorized-tone.mp3');
  final hasTools = Platform.isWindows && File('tools/ffmpeg.exe').existsSync();
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('syncbeat-public-test-');
    storage = PublicAudioStorage(
      supportDirectory: temp,
      downloadsDirectory: Directory('${temp.path}/Downloads'),
      android: false,
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PublicAudioStorage.channel, null);
    await temp.delete(recursive: true);
  });

  Future<StagedAudioFile> save() => storage.saveMp3(
    candidate: candidate,
    bytes: fixture.openRead(),
    expectedBytes: fixture.lengthSync(),
    onProgress: (_) {},
    cancellationToken: DownloadCancellationToken(),
  );

  test(
    'Downloads path comes from path_provider, including redirected location',
    () async {
      final original = PathProviderPlatform.instance;
      addTearDown(() => PathProviderPlatform.instance = original);
      PathProviderPlatform.instance = _Paths(
        '${temp.path}/redirected-downloads',
      );

      final value = await PublicAudioStorage(
        supportDirectory: temp,
      ).windowsDirectory;
      expect(value.path, contains('redirected-downloads'));
      expect(value.path, endsWith('SyncBeat'));
      expect(await value.exists(), isTrue);
    },
  );

  test(
    'native Windows Known Folder API resolves the actual Downloads path',
    () async {
      final path = await PathProviderWindows().getDownloadsPath();
      expect(path, isNotNull);
      expect(await Directory(path!).exists(), isTrue);
    },
    skip: !Platform.isWindows,
  );

  test(
    'short input is never published and private temporary files are removed',
    () async {
      await expectLater(
        storage.saveMp3(
          candidate: candidate,
          bytes: Stream.value([73, 68, 51, 0]),
          expectedBytes: 500,
          onProgress: (_) {},
          cancellationToken: DownloadCancellationToken(),
        ),
        throwsA(isA<AudioSourceException>()),
      );
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test(
    'real FFmpeg validation, public file, coherent manifests and library entry',
    () async {
      final file = await save();
      expect(file.path, contains('Downloads'));
      expect(await File(file.path).readAsBytes(), await fixture.readAsBytes());
      expect((await storage.list()).single.path, file.path);
      expect((await storage.findExistingCandidate(candidate))!.path, file.path);
      final manifest =
          jsonDecode(await File('${file.path}.json').readAsString()) as Map;
      expect(manifest['sha256'], file.sha256);
      expect(manifest['path'], file.path);
      expect(
        await temp.list().where((e) => e.path.contains('publish-')).isEmpty,
        isTrue,
      );
    },
    skip: !hasTools,
  );

  test(
    'deleted or modified published files are removed from library and duplicate lookup',
    () async {
      final file = await save();
      await File(file.path).writeAsBytes(List.filled(file.sizeBytes, 0));
      expect(await storage.findExistingCandidate(candidate), isNull);
      expect(await storage.list(), isEmpty);
      await File(file.path).delete();
      expect(await storage.list(), isEmpty);
    },
    skip: !hasTools,
  );

  test(
    'write failure leaves no definitive file and cleans private conversion copy',
    () async {
      await File('${temp.path}/blocked').writeAsString('not a directory');
      storage = PublicAudioStorage(
        supportDirectory: temp,
        downloadsDirectory: Directory('${temp.path}/blocked'),
      );
      await expectLater(save(), throwsA(isA<FileSystemException>()));
      expect(
        await temp.list().where((e) => e.path.contains('publish-')).isEmpty,
        isTrue,
      );
    },
    skip: !hasTools,
  );

  test(
    'valid header without MP3 frames is rejected before public copy',
    () async {
      await expectLater(
        storage.saveMp3(
          candidate: candidate,
          bytes: Stream.value([73, 68, 51, ...List.filled(100, 0)]),
          expectedBytes: 103,
          onProgress: (_) {},
          cancellationToken: DownloadCancellationToken(),
        ),
        throwsA(isA<AudioSourceException>()),
      );
      expect(await Directory('${temp.path}/Downloads').exists(), isFalse);
    },
    skip: !hasTools,
  );

  test(
    'Android channel contract publishes content URI and retains manifest; deleted URI disappears',
    () async {
      final calls = <String>[];
      final records = <String>[];
      var exists = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PublicAudioStorage.channel, (call) async {
            calls.add(call.method);
            if (call.method == 'validate') return null;
            if (call.method == 'publish') {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              final record =
                  jsonDecode(args['manifest'] as String)
                      as Map<String, dynamic>;
              record.addAll({
                'path': 'content://media/external/downloads/42',
                'fileName': args['name'],
              });
              records.add(jsonEncode(record));
              return {'path': record['path'], 'name': record['fileName']};
            }
            if (call.method == 'records') return records;
            if (call.method == 'verify') return exists;
            if (call.method == 'open') return null;
            throw PlatformException(code: 'UNEXPECTED');
          });
      storage = PublicAudioStorage(supportDirectory: temp, android: true);
      final file = await save();
      expect(calls.take(2), ['validate', 'publish']);
      expect((await storage.list()).single.path, file.path);
      expect((await storage.findExistingCandidate(candidate))!.path, file.path);
      await PublicAudioStorage.open(file.path);
      expect(calls.last, 'open');
      exists = false;
      expect(await storage.list(), isEmpty);
      expect(await storage.findExistingCandidate(candidate), isNull);
    },
  );

  test(
    'malformed Android records do not hide valid files or crash dedup',
    () async {
      final record = {
        'path': 'content://media/external/downloads/42',
        'fileName': 'valid.mp3',
        'sizeBytes': 20,
        'sha256': List.filled(64, 'a').join(),
        'stagedAt': DateTime.now().toUtc().toIso8601String(),
        'provider': candidate.providerId,
        'providerItemId': candidate.id,
      };
      final malformed = [
        '[]',
        '{}',
        '{',
        jsonEncode({...record, 'stagedAt': 'invalid date'}),
        jsonEncode({...record, 'sizeBytes': '20'}),
        jsonEncode({...record, 'fileName': null}),
        jsonEncode({...record, 'sha256': 12}),
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PublicAudioStorage.channel, (call) async {
            if (call.method == 'records') {
              return [...malformed, jsonEncode(record)];
            }
            if (call.method == 'verify') return true;
            throw PlatformException(code: 'UNEXPECTED');
          });
      storage = PublicAudioStorage(supportDirectory: temp, android: true);
      expect((await storage.list()).single.name, 'valid.mp3');
      expect(
        (await storage.findExistingCandidate(candidate))!.path,
        record['path'],
      );
    },
  );

  test(
    'Android publication error leaves no public library record or private temporary copy',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PublicAudioStorage.channel, (call) async {
            if (call.method == 'validate') return null;
            if (call.method == 'publish') {
              throw PlatformException(
                code: 'STORAGE',
                message: 'Spazio esaurito',
              );
            }
            return <String>[];
          });
      storage = PublicAudioStorage(supportDirectory: temp, android: true);
      await expectLater(save(), throwsA(isA<PlatformException>()));
      expect(await temp.list().toList(), isEmpty);
    },
  );
}
