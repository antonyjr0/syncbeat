import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/spotify_models.dart';
import 'audio_source.dart';
import 'youtube_models.dart';
import 'android_youtube_bridge.dart';
export 'youtube_models.dart';
export 'youtube_matcher.dart';
export 'youtube_associations.dart';

typedef ToolOutput = void Function(String line);

/// The general search can omit distributed audio entirely (e.g. VELENO).
/// Search both surfaces without opening each watch page; keep the best ten.
List<String> youtubeSearchQueries(SpotifyTrack track) => [
  'ytsearch10:${track.artistLine} ${track.title}',
  'ytsearch5:${track.artistLine} ${track.title} auto-generated',
];

/// Runs executables directly, never through a shell or user yt-dlp config.
class YoutubeTools {
  const YoutubeTools({
    this.executable = const String.fromEnvironment(
      'YT_DLP_PATH',
      defaultValue: 'yt-dlp.exe',
    ),
    this.ffmpegLocation = const String.fromEnvironment('FFMPEG_LOCATION'),
  });
  final String executable;
  final String ffmpegLocation;

  String get resolvedExecutable {
    if (executable != 'yt-dlp.exe') return executable;
    for (final base in [
      p.dirname(Platform.resolvedExecutable),
      Directory.current.path,
    ]) {
      final file = File(p.join(base, 'tools', 'yt-dlp.exe'));
      if (file.existsSync()) return file.path;
    }
    return executable;
  }

  String get resolvedFfmpegLocation {
    if (Platform.isAndroid) return '';
    if (ffmpegLocation.isNotEmpty) return ffmpegLocation;
    final adjacent = p.dirname(resolvedExecutable);
    final file = File(p.join(adjacent, 'ffmpeg.exe'));
    return file.existsSync() ? file.path : '';
  }

  Future<void> run(
    List<String> arguments, {
    required DownloadCancellationToken cancellation,
    required ToolOutput onLine,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (Platform.isAndroid) {
      return AndroidYoutubeBridge().run(
        arguments,
        cancellation: cancellation,
        onLine: onLine,
        timeout: timeout,
      );
    }
    cancellation.throwIfCancelled();
    final isSearch = arguments.contains('--dump-json');
    Process process;
    try {
      process = await Process.start(resolvedExecutable, [
        '--ignore-config',
        '--no-cache-dir',
        '--no-playlist',
        '--socket-timeout',
        isSearch ? '8' : '20',
        '--retries',
        isSearch ? '1' : '2',
        if (isSearch) ...['--extractor-retries', '1'],
        ...arguments,
      ], runInShell: false);
    } on ProcessException {
      throw const AudioSourceException(
        'yt-dlp non disponibile. Installa yt-dlp.exe nel PATH o configura YT_DLP_PATH.',
      );
    }
    var done = false;
    var timedOut = false;
    Future<void> stop() async {
      if (done) return;
      // /T also terminates FFmpeg children on Windows.
      if (Platform.isWindows) {
        await Process.run('taskkill.exe', [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ]);
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }

    unawaited(cancellation.whenCancelled.then((_) => stop()));
    final timer = Timer(timeout, () {
      timedOut = true;
      unawaited(stop());
    });
    final errors = <String>[];
    try {
      final stdout = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(onLine);
      final stderr = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            if (errors.length < 12) errors.add(line);
          });
      final code = await process.exitCode;
      await Future.wait([stdout, stderr]);
      cancellation.throwIfCancelled();
      if (timedOut) {
        throw const AudioSourceException(
          'Tempo massimo yt-dlp superato. Riprova.',
        );
      }
      if (code != 0) {
        throw AudioSourceException(
          'yt-dlp: ${errors.join('\n')} (codice $code). Verifica aggiornamenti, FFmpeg e accessibilità del video.',
        );
      }
    } finally {
      done = true;
      timer.cancel();
      process.kill();
    }
  }

  Future<List<YoutubeVideo>> search(
    SpotifyTrack track,
    DownloadCancellationToken cancellation,
  ) async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw const AudioSourceException(
        'La ricerca yt-dlp è disponibile su Windows e Android.',
      );
    }
    final videos = <YoutubeVideo>[];
    await run(
      [
        '--dump-json',
        '--flat-playlist',
        '--skip-download',
        '--ignore-errors',
        '--',
        ...youtubeSearchQueries(track),
      ],
      cancellation: cancellation,
      timeout: const Duration(seconds: 30),
      onLine: (line) {
        if (!line.startsWith('{')) return;
        final video = YoutubeVideo(jsonDecode(line) as Map<String, dynamic>);
        if (!videos.any((item) => item.id == video.id) && videos.length < 15) {
          videos.add(video);
        }
      },
    );
    if (videos.isEmpty) {
      throw const AudioSourceException(
        'Nessun video accessibile trovato. Controlla rete e versione yt-dlp.',
      );
    }
    return videos;
  }
}
