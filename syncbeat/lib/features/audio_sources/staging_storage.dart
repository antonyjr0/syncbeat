import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_source.dart';

abstract interface class AudioStagingStorage {
  Future<StagedAudioFile?> findExistingCandidate(AudioCandidate candidate);

  Future<StagedAudioFile> saveMp3({
    required AudioCandidate candidate,
    required Stream<List<int>> bytes,
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
    int? expectedBytes,
  });
}

class AppDirectoryStagingStorage implements AudioStagingStorage {
  AppDirectoryStagingStorage({
    this.applicationDirectory,
    this.maxFileSizeBytes = 120 * 1024 * 1024,
  });

  final Directory? applicationDirectory;
  final int maxFileSizeBytes;
  Directory? _resolvedDirectory;

  Future<Directory> get directory async {
    final existing = _resolvedDirectory;
    if (existing != null) return existing;
    final appDirectory =
        applicationDirectory ?? await getApplicationSupportDirectory();
    final staging = Directory(p.join(appDirectory.path, 'audio_staging'));
    await staging.create(recursive: true);
    _resolvedDirectory = staging;
    return staging;
  }

  @override
  Future<StagedAudioFile?> findExistingCandidate(
    AudioCandidate candidate,
  ) async {
    final targetDirectory = await directory;
    await for (final entity in targetDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.mp3.json')) continue;
      try {
        final manifest =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        if (manifest['provider'] != candidate.providerId ||
            manifest['providerItemId'] != _providerItemId(candidate)) {
          continue;
        }
        final fileName = manifest['fileName'] as String?;
        if (fileName == null) continue;
        final file = File(p.join(targetDirectory.path, fileName));
        if (!await file.exists()) continue;
        return StagedAudioFile(
          path: file.path,
          fileName: fileName,
          sizeBytes: (manifest['sizeBytes'] as num?)?.toInt() ?? 0,
          sha256: manifest['sha256'] as String? ?? '',
          candidate: candidate,
          stagedAt:
              DateTime.tryParse(manifest['stagedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return null;
  }

  static String sanitizeFileName(String input) {
    final safe = input
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    final truncated = safe.length > 100 ? safe.substring(0, 100).trim() : safe;
    return truncated.isEmpty ? 'audio' : truncated;
  }

  @override
  Future<StagedAudioFile> saveMp3({
    required AudioCandidate candidate,
    required Stream<List<int>> bytes,
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
    int? expectedBytes,
  }) async {
    if (expectedBytes != null && expectedBytes > maxFileSizeBytes) {
      throw const AudioSourceException(
        'Il file supera il limite di staging configurato.',
      );
    }
    final targetDirectory = await directory;
    final baseName = sanitizeFileName(
      '${candidate.title} - ${candidate.artist} - ${candidate.providerId}-${candidate.id}',
    );
    var file = File(p.join(targetDirectory.path, '$baseName.mp3'));
    var suffix = 1;
    while (await file.exists()) {
      file = File(p.join(targetDirectory.path, '$baseName-$suffix.mp3'));
      suffix++;
    }

    await file.create(exclusive: true);
    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    final hashSink = _DigestAccumulator();
    final hashInput = sha256.startChunkedConversion(hashSink);
    final iterator = StreamIterator<List<int>>(bytes);
    var receivedBytes = 0;
    final signature = <int>[];
    var signatureVerified = false;

    try {
      while (await Future.any<bool>([
        iterator.moveNext(),
        cancellationToken.whenCancelled.then((_) {
          throw const DownloadCancelledException();
        }),
      ])) {
        cancellationToken.throwIfCancelled();
        final chunk = iterator.current;
        if (chunk.isEmpty) continue;
        if (!signatureVerified) {
          signature.addAll(chunk.take(3 - signature.length));
          if (signature.length >= 3) {
            if (!_isMp3Signature(signature)) {
              throw const AudioSourceException(
                'Il contenuto ricevuto non è un file MP3 valido.',
              );
            }
            signatureVerified = true;
          }
        }
        receivedBytes += chunk.length;
        if (receivedBytes > maxFileSizeBytes) {
          throw const AudioSourceException(
            'Il file supera il limite di staging configurato.',
          );
        }
        hashInput.add(chunk);
        sink.add(chunk);
        onProgress(
          DownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: expectedBytes,
          ),
        );
      }
      cancellationToken.throwIfCancelled();
      if (signature.length < 3 || !_isMp3Signature(signature)) {
        throw const AudioSourceException(
          'Il file scaricato è vuoto o non è un MP3.',
        );
      }
      hashInput.close();
      await sink.flush();
      await sink.close();
      await iterator.cancel();
      final digest = hashSink.digest.toString();
      final manifestFile = File('${file.path}.json');
      final temporaryManifest = File('${manifestFile.path}.tmp');
      await temporaryManifest.writeAsString(
        jsonEncode({
          'fileName': p.basename(file.path),
          'sizeBytes': receivedBytes,
          'sha256': digest,
          'stagedAt': DateTime.now().toUtc().toIso8601String(),
          'provider': candidate.providerId,
          'providerItemId': _providerItemId(candidate),
          'sourceUrl': candidate.sourceUrl?.toString(),
          'downloadUrl': candidate.downloadUrl?.toString(),
          'track': {
            'title': candidate.title,
            'artist': candidate.artist,
            'durationSeconds': candidate.durationSeconds,
          },
          'spotifyTrack': candidate.spotifyTrackId == null
              ? null
              : {
                  'id': candidate.spotifyTrackId,
                  'title': candidate.spotifyTitle,
                  'artist': candidate.spotifyArtist,
                },
          'confidence': candidate.confidence,
          'quality': candidate.quality,
          'license': {
            'name': candidate.license.name,
            'url': candidate.license.url?.toString(),
            'attribution': candidate.license.attribution,
            'verified': candidate.license.verified,
            'downloadPermission': candidate.license.downloadPermission,
            'offlineUsePermission': candidate.license.offlineUsePermission,
            'apiAllowsDownload': candidate.apiAllowsDownload,
          },
        }),
        flush: true,
      );
      await temporaryManifest.rename(manifestFile.path);
      return StagedAudioFile(
        path: file.path,
        fileName: p.basename(file.path),
        sizeBytes: receivedBytes,
        sha256: digest,
        candidate: candidate,
        stagedAt: DateTime.now(),
      );
    } catch (_) {
      await iterator.cancel();
      await sink.close();
      final temporaryManifest = File('${file.path}.json.tmp');
      if (await temporaryManifest.exists()) {
        await temporaryManifest.delete();
      }
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  bool _isMp3Signature(List<int> bytes) {
    if (bytes.length < 3) return false;
    final hasId3Header =
        bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final hasMpegFrameSync = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
    return hasId3Header || hasMpegFrameSync;
  }

  String _providerItemId(AudioCandidate candidate) => candidate.isLocalFile
      ? sha256
            .convert(utf8.encode(candidate.localPath ?? candidate.id))
            .toString()
      : candidate.id;
}

class _DigestAccumulator implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}
