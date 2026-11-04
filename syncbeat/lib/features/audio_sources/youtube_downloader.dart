import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/spotify_models.dart';
import 'audio_source.dart';
import 'staging_storage.dart';
import 'youtube_provider.dart';

class YoutubeDownloadAuthorization {
  const YoutubeDownloadAuthorization({
    this.evidence = '',
    required this.rightsAndPlatformPermission,
    required this.conversionAndOfflineUse,
  });
  final String evidence;
  final bool rightsAndPlatformPermission;
  final bool conversionAndOfflineUse;
  bool get valid => rightsAndPlatformPermission && conversionAndOfflineUse;
}

class YoutubeDownloader {
  YoutubeDownloader({
    required this.tools,
    required this.storage,
    this.temporaryDirectory,
  });
  final YoutubeTools tools;
  final AudioStagingStorage storage;
  final Directory? temporaryDirectory;

  Future<StagedAudioFile> download({
    required SpotifyTrack track,
    required YoutubeVideo video,
    required YoutubeDownloadAuthorization authorization,
    required DownloadCancellationToken cancellation,
    required AudioDownloadProgress onProgress,
    void Function(String phase)? onPhase,
  }) async {
    if (!authorization.valid) {
      throw const AudioSourceException(
        'Servono autorizzazione al download e alla conversione/uso offline, compresi i permessi della piattaforma.',
      );
    }
    cancellation.throwIfCancelled();
    final candidate = AudioCandidate(
      id: video.id,
      providerId: 'youtube',
      title: video.title,
      artist: video.channel,
      durationSeconds: video.duration,
      sourceUrl: video.url,
      license: AudioLicense(
        name: 'Autorizzazione documentata dall’utente',
        verified: true,
        downloadPermission: true,
        offlineUsePermission: true,
        attribution: authorization.evidence.trim(),
      ),
    ).forSpotifyTrack(track);
    onPhase?.call('Controllo file già scaricati');
    final existing = await storage.findExistingCandidate(candidate);
    if (existing != null) return existing;
    onPhase?.call('Preparazione file temporanei');
    // Android's Dart system temp can be code_cache, which the native bridge
    // intentionally rejects. path_provider resolves Context.getCacheDir().
    final root =
        temporaryDirectory ??
        (Platform.isAndroid
            ? await getTemporaryDirectory()
            : Directory.systemTemp);
    final temp = await root.createTemp('syncbeat-youtube-');
    try {
      onPhase?.call('Download');
      await tools.run(
        [
          if (tools.resolvedFfmpegLocation.isNotEmpty) ...[
            '--ffmpeg-location',
            tools.resolvedFfmpegLocation,
          ],
          '--format',
          'bestaudio',
          '--extract-audio',
          '--audio-format',
          'mp3',
          '--audio-quality',
          '192K',
          '--max-filesize',
          '120M',
          '--no-overwrites',
          '--newline',
          '--progress',
          '--progress-template',
          'download:SYNCBEAT:%(progress)j',
          '--progress-template',
          'postprocess:SYNCBEAT_CONVERT:%(progress)j',
          '--output',
          p.join(temp.path, 'audio.%(ext)s'),
          '--',
          video.url.toString(),
        ],
        cancellation: cancellation,
        timeout: const Duration(minutes: 15),
        onLine: (line) {
          if (line.startsWith('SYNCBEAT_CONVERT:') ||
              line.contains('[ExtractAudio]')) {
            onPhase?.call('Conversione MP3');
          }
          if (!line.startsWith('SYNCBEAT:')) return;
          final data = jsonDecode(line.substring(9)) as Map<String, dynamic>;
          onProgress(
            DownloadProgress(
              receivedBytes: (data['downloaded_bytes'] as num?)?.toInt() ?? 0,
              totalBytes:
                  (data['total_bytes'] as num? ??
                          data['total_bytes_estimate'] as num?)
                      ?.toInt(),
            ),
          );
        },
      );
      cancellation.throwIfCancelled();
      final file = File(p.join(temp.path, 'audio.mp3'));
      if (!await file.exists() || await file.length() == 0) {
        throw const AudioSourceException(
          'Conversione MP3 non riuscita. Verifica FFmpeg.',
        );
      }
      onPhase?.call('Verifica e salvataggio in Download/SyncBeat');
      return await storage.saveMp3(
        candidate: candidate,
        bytes: file.openRead(),
        expectedBytes: await file.length(),
        onProgress: onProgress,
        cancellationToken: cancellation,
      );
    } finally {
      // Only this operation's private temporary files are removed.
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }
}
