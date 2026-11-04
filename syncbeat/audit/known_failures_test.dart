// Diagnostic audit regressions. All three pass after the 2026-11-04 fixes;
// kept separate so historical audit commands remain reproducible.
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/services/spotify_auth_service.dart';

class _Tokens implements SpotifyTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<SpotifyTokens?> read() async => null;
  @override
  Future<void> write(SpotifyTokens tokens) async {}
}

const candidate = AudioCandidate(
  id: 'audit-tone',
  providerId: 'local',
  title: 'Audit tone',
  artist: 'Synthetic',
  durationSeconds: 3,
  license: AudioLicense(name: 'Audit-generated signal'),
  isLocalFile: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global =
      null; // Real loopback cleanup, never Spotify endpoints.
  test(
    'AUD-01 failed browser launch must release Windows OAuth port',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final client = HttpClient();
      try {
        // Check no unrelated process is using the port before the probe.
        final before = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          8888,
        );
        await before.close(force: true);
        final bound = Completer<void>();
        final auth = SpotifyAuthService(
          secureTokenStore: _Tokens(),
          openExternal: (_) async {
            // The callback listener is started before browser opening.
            await Future<void>.delayed(const Duration(milliseconds: 100));
            bound.complete();
            return false;
          },
        );
        await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
        await bound.future;
        var released = true;
        try {
          final after = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            8888,
          );
          await after.close(force: true);
        } on SocketException {
          released = false;
        }
        if (!released) {
          // Complete only our abandoned listener to avoid leaving the probe bound.
          final response = await (await client.getUrl(
            Uri.parse('http://127.0.0.1:8888/callback'),
          )).close();
          await response.drain<void>();
        }
        expect(
          released,
          isTrue,
          reason: 'OAuth listener remained bound after failed browser launch',
        );
      } finally {
        client.close(force: true);
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: !Platform.isWindows,
  );
  test('AUD-02 deduplication must reject a corrupted cached MP3', () async {
    final dir = await Directory.systemTemp.createTemp(
      'syncbeat-audit-integrity-',
    );
    try {
      final storage = AppDirectoryStagingStorage(applicationDirectory: dir);
      final staged = await storage.saveMp3(
        candidate: candidate,
        bytes: Stream.value([0x49, 0x44, 0x33, 1, 2, 3]),
        expectedBytes: 6,
        onProgress: (_) {},
        cancellationToken: DownloadCancellationToken(),
      );
      await File(staged.path).writeAsBytes([0]);
      expect(
        await storage.findExistingCandidate(candidate),
        isNull,
        reason:
            'Size/hash are trusted from the manifest without checking the current file',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'AUD-03 staging must reject a stream shorter than expectedBytes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'syncbeat-audit-truncated-',
      );
      try {
        final storage = AppDirectoryStagingStorage(applicationDirectory: dir);
        await expectLater(
          storage.saveMp3(
            candidate: candidate,
            bytes: Stream.value([0x49, 0x44, 0x33, 1, 2, 3]),
            expectedBytes: 1000,
            onProgress: (_) {},
            cancellationToken: DownloadCancellationToken(),
          ),
          throwsA(isA<AudioSourceException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
