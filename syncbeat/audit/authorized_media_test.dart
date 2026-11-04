// Real Windows subprocess/network/codec audit; run explicitly, not as a mock.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';

void main() {
  test(
    'real authorized HTTP download, FFmpeg MP3 conversion, decode and staging',
    () async {
      final dir = Directory(p.absolute('tools/audit/authorized-media'));
      await dir.create(recursive: true);
      final runtime = const bool.fromEnvironment('AUDIT_BUNDLED_TOOLS')
          ? p.absolute('build/windows/x64/runner/Release/tools')
          : p.absolute('tools');
      final ffmpeg = p.join(runtime, 'ffmpeg.exe');
      final wav = File(p.join(dir.path, 'authorized-tone.wav'));
      final generated = await Process.run(ffmpeg, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=3',
        '-c:a',
        'pcm_s16le',
        '-y',
        wav.path,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      const permission =
          'Synthetic 440 Hz test signal generated locally for this audit. Download from this operator-controlled loopback server, MP3 conversion, copying and offline playback are explicitly permitted. No third-party recording or YouTube media is used.';
      await File(p.join(dir.path, 'PERMISSION.txt')).writeAsString(permission);
      final bytes = await wav.readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        try {
          if (request.uri.path != '/authorized-tone.wav') {
            request.response.statusCode = 404;
          } else {
            requests++;
            request.response.headers.contentType = ContentType('audio', 'wav');
            request.response.contentLength = bytes.length;
            if (request.method != 'HEAD') request.response.add(bytes);
          }
          await request.response.close();
        } on HttpException {
          /* client cancellation */
        }
      });
      try {
        final uri = Uri.parse(
          'http://127.0.0.1:${server.port}/authorized-tone.wav',
        );
        final lines = <String>[];
        final output = p.join(dir.path, 'converted.%(ext)s');
        await YoutubeTools(executable: p.join(runtime, 'yt-dlp.exe')).run(
          [
            '--ffmpeg-location',
            const bool.fromEnvironment('AUDIT_FFMPEG_FILE')
                ? ffmpeg
                : p.dirname(ffmpeg),
            '--format',
            'bestaudio',
            '--extract-audio',
            '--audio-format',
            'mp3',
            '--audio-quality',
            '192K',
            '--force-overwrites',
            '--newline',
            '--progress',
            '--progress-template',
            'download:SYNCBEAT:%(progress)j',
            '--output',
            output,
            '--',
            uri.toString(),
          ],
          cancellation: DownloadCancellationToken(),
          onLine: lines.add,
        );
        final mp3 = File(p.join(dir.path, 'converted.mp3'));
        expect(await mp3.exists(), isTrue);
        final probe = await Process.run(p.absolute('tools/ffprobe.exe'), [
          '-v',
          'error',
          '-show_entries',
          'stream=codec_name',
          '-show_entries',
          'format=duration',
          '-of',
          'json',
          mp3.path,
        ]);
        expect(probe.exitCode, 0);
        final metadata =
            jsonDecode(probe.stdout as String) as Map<String, dynamic>;
        expect(metadata['streams'][0]['codec_name'], 'mp3');
        final decoded = await Process.run(ffmpeg, [
          '-v',
          'error',
          '-i',
          mp3.path,
          '-f',
          'null',
          '-',
        ]);
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
        final storage = AppDirectoryStagingStorage(
          applicationDirectory: Directory(
            p.join(
              dir.path,
              'staging-${DateTime.now().microsecondsSinceEpoch}',
            ),
          ),
        );
        final candidate = AudioCandidate(
          id: 'authorized-tone-440hz-3s',
          providerId: 'audit-http',
          title: 'Authorized tone 440 Hz',
          artist: 'Synthetic audit signal',
          durationSeconds: 3,
          sourceUrl: uri,
          license: const AudioLicense(
            name: 'Explicit audit permission',
            attribution: permission,
            verified: true,
            downloadPermission: true,
            offlineUsePermission: true,
          ),
        );
        final progress = <DownloadProgress>[];
        final staged = await storage.saveMp3(
          candidate: candidate,
          bytes: mp3.openRead(),
          expectedBytes: await mp3.length(),
          onProgress: progress.add,
          cancellationToken: DownloadCancellationToken(),
        );
        expect(
          (await storage.findExistingCandidate(candidate))?.path,
          staged.path,
        );
        expect(
          staged.sha256,
          sha256.convert(await mp3.readAsBytes()).toString(),
        );
        expect(progress.last.fraction, 1);
        expect(lines.any((line) => line.startsWith('SYNCBEAT:')), isTrue);
        final report = {
          'runtime': runtime,
          'authorizedSource':
              'operator-controlled loopback HTTP server; synthetic signal',
          'permission': permission,
          'requests': requests,
          'mp3Codec': metadata['streams'][0]['codec_name'],
          'duration': metadata['format']['duration'],
          'stagedPath': staged.path,
          'sha256': staged.sha256,
          'ytDlpProgressObserved': true,
          'fullDecodeExitCode': decoded.exitCode,
          'audiblePlaybackVerified': false,
          'youtubeTransportVerified': false,
        };
        await File(
          p.join(dir.path, 'evidence.json'),
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        final context = const bool.fromEnvironment('AUDIT_BUNDLED_TOOLS')
            ? 'bundled'
            : const bool.fromEnvironment('AUDIT_FFMPEG_FILE')
            ? 'explicit-ffmpeg'
            : 'development';
        await File(
          p.join(dir.path, 'evidence-$context.json'),
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      } finally {
        await server.close(force: true);
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
