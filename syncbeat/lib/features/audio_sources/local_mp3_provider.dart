import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:haudiotagger/haudiotagger.dart';
import 'package:path/path.dart' as p;

import '../../models/spotify_models.dart';
import 'audio_source.dart';
import 'staging_storage.dart';

class LocalMp3File {
  const LocalMp3File({
    required this.name,
    required this.openRead,
    required this.readBytes,
    this.sizeBytes,
    this.path,
  });

  final String name;
  final String? path;
  final Stream<List<int>> Function() openRead;
  final Future<Uint8List> Function() readBytes;
  final int? sizeBytes;
}

class LocalAudioMetadata {
  const LocalAudioMetadata({
    this.title,
    this.artist,
    this.durationSeconds,
    this.codec,
  });

  final String? title;
  final String? artist;
  final int? durationSeconds;
  final String? codec;
}

abstract interface class LocalMp3TagReader {
  Future<LocalAudioMetadata?> read(LocalMp3File file);
}

class HaudiotaggerMp3TagReader implements LocalMp3TagReader {
  @override
  Future<LocalAudioMetadata?> read(LocalMp3File file) async {
    final path = file.path;
    if (path != null && await File(path).exists()) {
      final tag = await Haudiotagger.read(path);
      final properties = await Haudiotagger.readProperties(path);
      final durationMicros = properties.durationMicros?.toInt();
      return LocalAudioMetadata(
        title: tag?.title,
        artist: tag?.trackArtist,
        durationSeconds: durationMicros == null
            ? tag?.duration
            : durationMicros ~/ Duration.microsecondsPerSecond,
        codec: properties.codec,
      );
    }
    final bytes = await file.readBytes();
    final tag = await Haudiotagger.readFromBytes(bytes);
    final properties = await Haudiotagger.readPropertiesFromBytes(bytes);
    final durationMicros = properties.durationMicros?.toInt();
    return LocalAudioMetadata(
      title: tag?.title,
      artist: tag?.trackArtist,
      durationSeconds: durationMicros == null
          ? tag?.duration
          : durationMicros ~/ Duration.microsecondsPerSecond,
      codec: properties.codec,
    );
  }
}

typedef LocalMp3Picker = Future<List<LocalMp3File>> Function();

class LocalMp3Provider implements AudioSourceProvider, AudioSourceDownloader {
  LocalMp3Provider({
    required this.stagingStorage,
    LocalMp3Picker? picker,
    LocalMp3TagReader? tagReader,
  }) : _picker = picker ?? _pickMp3Files,
       _tagReader = tagReader ?? HaudiotaggerMp3TagReader();

  final AudioStagingStorage stagingStorage;
  final LocalMp3Picker _picker;
  final LocalMp3TagReader _tagReader;
  final Map<String, AudioCandidate> _selectedFiles = {};

  @override
  String get id => 'local';

  @override
  String get displayName => 'File MP3 locali';

  @override
  Future<List<AudioCandidate>> search(SpotifyTrack track) async =>
      List.unmodifiable(_selectedFiles.values);

  Future<List<AudioCandidate>> pickFiles({
    required bool userConfirmedRights,
  }) async {
    if (!userConfirmedRights) {
      throw AudioSourceException(
        'Conferma di avere i diritti per usare questi file MP3 offline.',
        sourceId: id,
      );
    }
    final files = await _picker();
    final candidates = <AudioCandidate>[];
    for (final file in files) {
      if (p.extension(file.name).toLowerCase() != '.mp3') continue;
      try {
        final metadata = await _tagReader.read(file);
        final codec = metadata?.codec?.toLowerCase();
        if (codec != null &&
            codec.isNotEmpty &&
            codec != 'mp3' &&
            codec != 'mpeg') {
          continue;
        }
        final parsedName = _parseFilename(file.name);
        final title = _firstNonEmpty(metadata?.title, parsedName.$2);
        final artist = _firstNonEmpty(metadata?.artist, parsedName.$1);
        final candidateId = file.path ?? file.name;
        final candidate = AudioCandidate(
          id: candidateId,
          providerId: id,
          title: title,
          artist: artist,
          durationSeconds: metadata?.durationSeconds ?? 0,
          license: const AudioLicense(
            name: 'File locale · diritti dichiarati dall’utente',
            verified: false,
            downloadPermission: true,
            offlineUsePermission: true,
            attribution: 'File selezionato dall’utente',
          ),
          quality: 'MP3 locale',
          estimatedFileSizeBytes: file.sizeBytes,
          isLocalFile: true,
          localPath: file.path,
          userSelectedBytes: file.openRead,
        );
        _selectedFiles[candidate.id] = candidate;
        candidates.add(candidate);
      } on Exception {
        continue;
      }
    }
    return List.unmodifiable(candidates);
  }

  @override
  bool canDownload(AudioCandidate candidate) =>
      candidate.providerId == id &&
      candidate.isLocalFile &&
      candidate.license.offlineUsePermission &&
      (candidate.localPath != null || candidate.userSelectedBytes != null);

  @override
  Future<StagedAudioFile> download(
    AudioCandidate candidate, {
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
  }) async {
    if (!canDownload(candidate)) {
      throw const AudioSourceException(
        'Seleziona un MP3 locale e conferma i diritti d’uso prima di copiarlo nello staging.',
        sourceId: 'local',
      );
    }
    final existing = await stagingStorage.findExistingCandidate(candidate);
    if (existing != null) return existing;
    final stream =
        candidate.userSelectedBytes?.call() ??
        File(candidate.localPath!).openRead();
    return stagingStorage.saveMp3(
      candidate: candidate,
      bytes: stream,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }

  static Future<List<LocalMp3File>> _pickMp3Files() async {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
    );
    return pickedFiles
        .map(
          (file) => LocalMp3File(
            name: file.name,
            path: file.path,
            sizeBytes: file.lengthSync(),
            openRead: file.readAsByteStream,
            readBytes: file.readAsBytes,
          ),
        )
        .toList(growable: false);
  }

  (String, String) _parseFilename(String fileName) {
    final stem = p.basenameWithoutExtension(fileName).trim();
    final split = RegExp(r'^(.+?)\s+-\s+(.+)$').firstMatch(stem);
    if (split == null) return ('', stem);
    return (split.group(1)!.trim(), split.group(2)!.trim());
  }

  String _firstNonEmpty(String? preferred, String fallback) =>
      preferred?.trim().isNotEmpty == true ? preferred!.trim() : fallback;
}
