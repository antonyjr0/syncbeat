import 'dart:async';

import '../../models/spotify_models.dart';

abstract interface class AudioSourceProvider {
  String get id;
  String get displayName;

  Future<List<AudioCandidate>> search(SpotifyTrack track);
}

abstract interface class AudioSourceDownloader {
  String get id;

  bool canDownload(AudioCandidate candidate);

  Future<StagedAudioFile> download(
    AudioCandidate candidate, {
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
  });
}

typedef AudioDownloadProgress = void Function(DownloadProgress progress);

class DownloadProgress {
  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }
}

class DownloadCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const DownloadCancelledException();
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download annullato.';
}

class AudioLicense {
  const AudioLicense({
    required this.name,
    this.url,
    this.attribution,
    this.verified = false,
    this.downloadPermission = false,
    this.offlineUsePermission = false,
    this.restrictionReason,
  });

  final String name;
  final Uri? url;
  final String? attribution;
  final bool verified;
  final bool downloadPermission;
  final bool offlineUsePermission;
  final String? restrictionReason;

  bool get permitsOfflineUse =>
      verified && downloadPermission && offlineUsePermission;
}

class AudioCandidate {
  const AudioCandidate({
    required this.id,
    required this.providerId,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.license,
    this.downloadUrl,
    this.sourceUrl,
    this.quality,
    this.estimatedFileSizeBytes,
    this.apiAllowsDownload = false,
    this.isLocalFile = false,
    this.localPath,
    this.userSelectedBytes,
    this.spotifyTrackId,
    this.spotifyTitle,
    this.spotifyArtist,
    this.confidence = 0,
  });

  final String id;
  final String providerId;
  final String title;
  final String artist;
  final int durationSeconds;
  final AudioLicense license;
  final Uri? downloadUrl;
  final Uri? sourceUrl;
  final String? quality;
  final int? estimatedFileSizeBytes;
  final bool apiAllowsDownload;
  final bool isLocalFile;
  final String? localPath;
  final Stream<List<int>> Function()? userSelectedBytes;
  final String? spotifyTrackId;
  final String? spotifyTitle;
  final String? spotifyArtist;
  final double confidence;

  bool get isAuthorizedDownload =>
      !isLocalFile &&
      apiAllowsDownload &&
      downloadUrl != null &&
      license.permitsOfflineUse;

  bool get canStage => isLocalFile || isAuthorizedDownload;

  int? get estimatedSizeBytes =>
      estimatedFileSizeBytes ??
      (durationSeconds > 0 ? durationSeconds * 24000 : null);

  AudioCandidate withConfidence(double value) => AudioCandidate(
    id: id,
    providerId: providerId,
    title: title,
    artist: artist,
    durationSeconds: durationSeconds,
    license: license,
    downloadUrl: downloadUrl,
    sourceUrl: sourceUrl,
    quality: quality,
    estimatedFileSizeBytes: estimatedFileSizeBytes,
    apiAllowsDownload: apiAllowsDownload,
    isLocalFile: isLocalFile,
    localPath: localPath,
    userSelectedBytes: userSelectedBytes,
    spotifyTrackId: spotifyTrackId,
    spotifyTitle: spotifyTitle,
    spotifyArtist: spotifyArtist,
    confidence: value,
  );

  AudioCandidate forSpotifyTrack(SpotifyTrack track) => AudioCandidate(
    id: id,
    providerId: providerId,
    title: title,
    artist: artist,
    durationSeconds: durationSeconds,
    license: license,
    downloadUrl: downloadUrl,
    sourceUrl: sourceUrl,
    quality: quality,
    estimatedFileSizeBytes: estimatedFileSizeBytes,
    apiAllowsDownload: apiAllowsDownload,
    isLocalFile: isLocalFile,
    localPath: localPath,
    userSelectedBytes: userSelectedBytes,
    spotifyTrackId: track.id,
    spotifyTitle: track.title,
    spotifyArtist: track.artistLine,
    confidence: confidence,
  );
}

class AudioDownloadManager {
  AudioDownloadManager(Iterable<AudioSourceDownloader> downloaders)
    : _downloaders = {
        for (final downloader in downloaders) downloader.id: downloader,
      };

  final Map<String, AudioSourceDownloader> _downloaders;

  bool canDownload(AudioCandidate candidate) =>
      _downloaders[candidate.providerId]?.canDownload(candidate) ?? false;

  Future<StagedAudioFile> download(
    AudioCandidate candidate, {
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
  }) async {
    final downloader = _downloaders[candidate.providerId];
    if (downloader == null || !downloader.canDownload(candidate)) {
      throw AudioSourceException(
        candidate.license.restrictionReason ??
            'Questo risultato non ha un download autorizzato.',
        sourceId: candidate.providerId,
      );
    }
    return downloader.download(
      candidate,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }
}

enum TrackMatchStatus { noMatch, confident, manualSelectionRequired }

class ScoredAudioCandidate {
  const ScoredAudioCandidate({
    required this.candidate,
    required this.confidence,
  });

  final AudioCandidate candidate;
  final double confidence;
}

class AudioMatchResult {
  const AudioMatchResult({
    required this.track,
    required this.candidates,
    required this.status,
  });

  final SpotifyTrack track;
  final List<ScoredAudioCandidate> candidates;
  final TrackMatchStatus status;

  bool get requiresManualSelection =>
      status == TrackMatchStatus.manualSelectionRequired;
}

class StagedAudioFile {
  const StagedAudioFile({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.candidate,
    required this.stagedAt,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final AudioCandidate candidate;
  final DateTime stagedAt;
}

class AudioSourceException implements Exception {
  const AudioSourceException(this.message, {this.sourceId});

  final String message;
  final String? sourceId;

  @override
  String toString() => message;
}
