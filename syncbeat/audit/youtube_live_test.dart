import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';
import 'package:syncbeat/models/spotify_models.dart';

void main() {
  test(
    'live YouTube metadata search includes and ranks the artist VELENO recording',
    () async {
      const track = SpotifyTrack(
        id: 'audit-reference-not-a-spotify-import',
        title: 'VELENO',
        artists: ['Tananai'],
        album: 'CALMOCOBRA',
        durationMs: 199000,
        isLocal: false,
      );
      final tools = YoutubeTools(
        executable: p.absolute(
          'build/windows/x64/runner/Release/tools/yt-dlp.exe',
        ),
      );
      final timer = Stopwatch()..start();
      final videos = await tools.search(track, DownloadCancellationToken());
      timer.stop();
      final ranked = const YoutubeMatcher()
          .rank(track, videos)
          .take(10)
          .toList();
      await File('tools/audit/youtube-live.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'referenceMetadata':
              'manually specified VELENO / Tananai / 199 seconds; not a live Spotify import',
          'retrievedCount': videos.length,
          'elapsedMilliseconds': timer.elapsedMilliseconds,
          'searchMode':
              'flat-playlist; two search queries; no per-video extraction',
          'displayedCount': ranked.length,
          'results': [
            for (final result in ranked)
              {
                'id': result.video.id,
                'title': result.video.title,
                'channel': result.video.channel,
                'score': result.score,
                'oac': result.video.channelInfo!.oac.name,
                'verification': result.video.channelInfo!.verification.name,
              },
          ],
          'audioDownloaded': false,
        }),
      );
      expect(ranked.first.video.id, 'PzYnwqUGI7Q');
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
