import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';
import 'package:syncbeat/models/spotify_models.dart';

class _SearchTools extends YoutubeTools {
  _SearchTools(this.fixture);
  final Map<String, dynamic> fixture;
  List<String>? arguments;
  Duration? requestedTimeout;
  @override
  Future<void> run(
    List<String> arguments, {
    required DownloadCancellationToken cancellation,
    required ToolOutput onLine,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    this.arguments = arguments;
    requestedTimeout = timeout;
    for (final result in [
      ...fixture['general'] as List,
      ...fixture['supplemental'] as List,
      ...(fixture['general'] as List).take(2),
    ]) {
      cancellation.throwIfCancelled();
      onLine(jsonEncode(result));
    }
  }
}

void main() {
  late Map<String, dynamic> fixture;
  late SpotifyTrack track;
  setUp(() {
    fixture =
        jsonDecode(File('test/fixtures/veleno_search.json').readAsStringSync())
            as Map<String, dynamic>;
    final data = fixture['track'] as Map<String, dynamic>;
    track = SpotifyTrack(
      id: data['id'],
      title: data['title'],
      artists: List<String>.from(data['artists']),
      album: data['album'],
      durationMs: data['durationMs'],
      isLocal: false,
    );
  });
  test(
    'VELENO original is absent from general search but wins after supplemental discovery',
    () async {
      final general = (fixture['general'] as List).map(
        (v) => YoutubeVideo(Map<String, dynamic>.from(v)),
      );
      expect(general.any((v) => v.id == 'PzYnwqUGI7Q'), isFalse);
      expect(
        const YoutubeMatcher().rank(track, general).first.video.id,
        'iDMNw0CbSvg',
      );
      final tools = _SearchTools(fixture);
      final videos = await tools.search(track, DownloadCancellationToken());
      expect(tools.arguments, contains('--flat-playlist'));
      expect(tools.requestedTimeout, const Duration(seconds: 30));
      expect(
        tools.arguments,
        contains('ytsearch5:Tananai VELENO auto-generated'),
      );
      expect(videos.map((v) => v.id).toSet().length, videos.length);
      final ranked = const YoutubeMatcher()
          .rank(track, videos)
          .take(10)
          .toList();
      expect(ranked.length, 10);
      expect(ranked.first.video.id, 'PzYnwqUGI7Q');
      expect(ranked.first.score, closeTo(96.4, .001));
      expect(ranked.first.video.title, 'VELENO');
      expect(
        ranked.first.score,
        greaterThan(
          ranked.firstWhere((r) => r.video.id == 'iDMNw0CbSvg').score,
        ),
      );
      // Neither verification nor the artist's name is converted into OAC proof.
      expect(ranked.first.video.channelInfo!.oac.name, 'unknown');
    },
  );
  test(
    'flat search retains ranking and thumbnails without extracting video details',
    () {
      final data =
          jsonDecode(
                File(
                  'test/fixtures/youtube_flat_search.json',
                ).readAsStringSync(),
              )
              as List<dynamic>;
      final videos = data
          .map((row) => YoutubeVideo(row as Map<String, dynamic>))
          .toList();
      expect(
        videos.every((video) => video.metadata['description'] == null),
        isTrue,
      );
      expect(
        videos.every(
          (video) => video.thumbnail?.startsWith('https://') == true,
        ),
        isTrue,
      );
      final ranked = const YoutubeMatcher().rank(track, videos);
      expect(ranked.first.video.id, 'PzYnwqUGI7Q');
      expect(ranked.first.video.channelInfo!.oac.name, 'unknown');
    },
  );
  test(
    'artist name in upload title is equivalent for title similarity, not better than structured artist metadata',
    () {
      final videos = [
        (fixture['general'] as List).firstWhere(
          (v) => v['id'] == 'iDMNw0CbSvg',
        ),
        (fixture['supplemental'] as List).single,
      ].map((v) => YoutubeVideo(Map<String, dynamic>.from(v)));
      final ranked = const YoutubeMatcher().rank(track, videos);
      expect(
        ranked.every(
          (r) =>
              r.reasons.contains('Titolo 100% · Artisti/collaborazioni 100%'),
        ),
        isTrue,
      );
      expect(ranked.first.video.id, 'PzYnwqUGI7Q');
    },
  );
}
