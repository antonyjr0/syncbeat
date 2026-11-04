import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';

/// Explicit integration check: writes one own synthetic tone to real Downloads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real Windows Downloads publication and read-back', () async {
    PathProviderWindows.registerWith();
    final support = Directory('tools/public-audio-checks/support').absolute;
    await support.create(recursive: true);
    final storage = PublicAudioStorage(supportDirectory: support);
    final input = File('test/fixtures/authorized-tone.mp3');
    const candidate = AudioCandidate(
      id: 'synthetic-tone-public-audit',
      providerId: 'own-audio',
      title: 'SyncBeat test tone',
      artist: 'Synthetic 440 Hz',
      durationSeconds: 1,
      license: AudioLicense(
        name: 'CC0-1.0 synthetic test tone',
        verified: true,
        downloadPermission: true,
        offlineUsePermission: true,
        attribution: 'test/fixtures/authorized-tone.LICENSE.txt',
      ),
    );
    final existing = await storage.findExistingCandidate(candidate);
    final file =
        existing ??
        await storage.saveMp3(
          candidate: candidate,
          bytes: input.openRead(),
          expectedBytes: await input.length(),
          onProgress: (_) {},
          cancellationToken: DownloadCancellationToken(),
        );
    expect(await File(file.path).readAsBytes(), await input.readAsBytes());
    expect(
      (await storage.list()).any((entry) => entry.path == file.path),
      isTrue,
    );
    expect((await storage.findExistingCandidate(candidate))!.path, file.path);
    await File('tools/public-audio-checks/real-downloads.json').writeAsString(
      jsonEncode({
        'path': file.path,
        'sizeBytes': file.sizeBytes,
        'sha256': file.sha256,
        'ffmpegDecoded': true,
        'libraryReadBack': true,
        'humanAudiblePlaybackVerified': false,
        'youtubeNetworkDownloadVerified': false,
      }),
      flush: true,
    );
  }, skip: !Platform.isWindows);
}
