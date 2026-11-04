import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'audio_source.dart';
import 'staging_storage.dart';
import 'youtube_provider.dart';

class PublishedAudio {
  const PublishedAudio(this.path, this.name);
  final String path;
  final String name;
}

/// Conversion stays private. Only validated, completed audio reaches Downloads.
class PublicAudioStorage implements AudioStagingStorage {
  PublicAudioStorage({
    this.supportDirectory,
    this.downloadsDirectory,
    this.android,
  });
  final Directory? supportDirectory;
  final Directory? downloadsDirectory;
  final bool? android;
  bool get _android => android ?? Platform.isAndroid;
  static const channel = MethodChannel('syncbeat/public_audio');

  Future<Directory> get _support async =>
      supportDirectory ?? await getApplicationSupportDirectory();
  Future<Directory> get windowsDirectory async {
    // path_provider_windows calls SHGetKnownFolderPath(FOLDERID_Downloads).
    final root = downloadsDirectory ?? await getDownloadsDirectory();
    if (root == null) {
      throw const AudioSourceException('Cartella Download non disponibile.');
    }
    final directory = Directory(p.join(root.path, 'SyncBeat'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<bool> _valid(Map<String, dynamic> data) async {
    try {
      // Validate every field consumed by list()/dedup before trusting a record.
      // A single damaged sidecar must not disable the whole library.
      final path = data['path'];
      final name = data['fileName'];
      final size = data['sizeBytes'];
      final hash = data['sha256'];
      final stagedAt = data['stagedAt'];
      if (path is! String ||
          path.isEmpty ||
          name is! String ||
          name.isEmpty ||
          p.basename(name) != name ||
          size is! int ||
          size <= 0 ||
          hash is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
          stagedAt is! String ||
          DateTime.tryParse(stagedAt) == null ||
          data['provider'] is! String ||
          data['providerItemId'] is! String) {
        return false;
      }
      if (path.startsWith('content://')) {
        return await channel.invokeMethod<bool>('verify', data) ?? false;
      }
      final file = File(path);
      return await file.exists() &&
          await file.length() == data['sizeBytes'] &&
          (await sha256.bind(file.openRead()).first).toString() ==
              data['sha256'];
    } on FileSystemException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _records() async {
    final records = <Map<String, dynamic>>[];
    if (_android) {
      final values = await channel.invokeListMethod<String>('records') ?? [];
      for (final value in values) {
        try {
          final data = jsonDecode(value) as Map<String, dynamic>;
          if (await _valid(data)) records.add(data);
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
      return records;
    }
    await for (final entry in (await windowsDirectory).list()) {
      if (entry is! File || !entry.path.endsWith('.mp3.json')) continue;
      try {
        final data =
            jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        if (data['path'] != entry.path.substring(0, entry.path.length - 5)) {
          continue;
        }
        if (await _valid(data)) records.add(data);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return records;
  }

  Future<List<PublishedAudio>> list() async => [
    for (final record in await _records())
      PublishedAudio(record['path'] as String, record['fileName'] as String),
  ];

  @override
  Future<StagedAudioFile?> findExistingCandidate(
    AudioCandidate candidate,
  ) async {
    for (final data in await _records()) {
      if (data['provider'] == candidate.providerId &&
          data['providerItemId'] == candidate.id) {
        return StagedAudioFile(
          path: data['path'] as String,
          fileName: data['fileName'] as String,
          sizeBytes: data['sizeBytes'] as int,
          sha256: data['sha256'] as String,
          candidate: candidate,
          stagedAt: DateTime.parse(data['stagedAt'] as String),
        );
      }
    }
    return null;
  }

  @override
  Future<StagedAudioFile> saveMp3({
    required AudioCandidate candidate,
    required Stream<List<int>> bytes,
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
    int? expectedBytes,
  }) async {
    final temp = await Directory((await _support).path).createTemp('publish-');
    try {
      final staged =
          await AppDirectoryStagingStorage(applicationDirectory: temp).saveMp3(
            candidate: candidate,
            bytes: bytes,
            expectedBytes: expectedBytes,
            onProgress: onProgress,
            cancellationToken: cancellationToken,
          );
      cancellationToken.throwIfCancelled();
      onProgress(const DownloadProgress(receivedBytes: 0));
      if (_android) {
        await channel.invokeMethod<void>('validate', {'path': staged.path});
      } else {
        final tools = const YoutubeTools();
        final location = tools.resolvedFfmpegLocation;
        final executable = location.isEmpty
            ? 'ffmpeg.exe'
            : (location.endsWith('.exe')
                  ? location
                  : p.join(location, 'ffmpeg.exe'));
        final probe = await Process.run(
          location.isEmpty
              ? 'ffprobe.exe'
              : p.join(p.dirname(executable), 'ffprobe.exe'),
          [
            '-v',
            'error',
            '-show_entries',
            'stream=codec_name',
            '-of',
            'json',
            staged.path,
          ],
        ).timeout(const Duration(seconds: 30));
        final streams = probe.exitCode == 0
            ? (jsonDecode(probe.stdout as String)
                      as Map<String, dynamic>)['streams']
                  as List<dynamic>
            : <dynamic>[];
        if (streams.length != 1 ||
            (streams.first as Map<String, dynamic>)['codec_name'] != 'mp3') {
          throw const AudioSourceException(
            'Il file convertito non contiene audio MP3 valido.',
          );
        }
        final process = await Process.start(executable, [
          '-v',
          'error',
          '-xerror',
          '-i',
          staged.path,
          '-f',
          'null',
          '-',
        ]);
        var complete = false;
        cancellationToken.whenCancelled.then((_) {
          if (!complete) process.kill();
        });
        final error = process.stderr.transform(utf8.decoder).join();
        final output = process.stdout.drain<void>();
        final exit = await process.exitCode.timeout(
          const Duration(minutes: 2),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        complete = true;
        await output;
        final message = await error;
        cancellationToken.throwIfCancelled();
        if (exit != 0) throw AudioSourceException('MP3 non valido: $message');
      }
      final manifest =
          jsonDecode(await File('${staged.path}.json').readAsString())
              as Map<String, dynamic>;
      cancellationToken.throwIfCancelled();
      final id =
          '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1000000000).toString().padLeft(9, '0')}';
      String path;
      String name;
      String? pendingPath;
      if (_android) {
        var complete = false;
        cancellationToken.whenCancelled.then((_) {
          if (!complete) {
            channel.invokeMethod<void>('cancel', {'id': id}).catchError((_) {});
          }
        });
        try {
          final result = await channel
              .invokeMapMethod<String, dynamic>('publish', {
                'id': id,
                'path': staged.path,
                'name': staged.fileName,
                'sizeBytes': staged.sizeBytes,
                'sha256': staged.sha256,
                'manifest': jsonEncode(manifest),
              });
          path = result!['path'] as String;
          name = result['name'] as String;
        } finally {
          complete = true;
        }
      } else {
        final dir = await windowsDirectory;
        // Unique name avoids accidental overwrites, even across app instances.
        name = '${p.basenameWithoutExtension(staged.fileName)}-$id.mp3';
        final part = File(p.join(dir.path, '$name.part'));
        var prepared = false;
        try {
          final sink = part.openWrite();
          try {
            await for (final chunk in File(staged.path).openRead()) {
              cancellationToken.throwIfCancelled();
              sink.add(chunk);
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          cancellationToken.throwIfCancelled();
          if (await part.length() != staged.sizeBytes ||
              (await sha256.bind(part.openRead()).first).toString() !=
                  staged.sha256) {
            throw const AudioSourceException(
              'Errore di integrità durante il salvataggio.',
            );
          }
          path = p.join(dir.path, name);
          pendingPath = part.path;
          prepared = true;
        } finally {
          if (!prepared && await part.exists()) await part.delete();
        }
      }
      manifest.addAll({'path': path, 'fileName': name});
      // Private manifest preserves authorisation and source metadata; no temp paths.
      if (!_android) {
        final sidecar = File('$path.json');
        final temporarySidecar = File('$path.json.tmp');
        try {
          await temporarySidecar.writeAsString(
            jsonEncode(manifest),
            flush: true,
          );
          await temporarySidecar.rename(sidecar.path);
          cancellationToken.throwIfCancelled();
          await File(pendingPath!).rename(path);
        } catch (_) {
          for (final file in [
            File(path),
            sidecar,
            temporarySidecar,
            if (pendingPath != null) File(pendingPath),
          ]) {
            if (await file.exists()) await file.delete();
          }
          rethrow;
        }
      }
      return StagedAudioFile(
        path: path,
        fileName: name,
        sizeBytes: staged.sizeBytes,
        sha256: staged.sha256,
        candidate: candidate,
        stagedAt: staged.stagedAt,
      );
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  static Future<void> open(String path, {bool folder = false}) async {
    if (path.startsWith('content://')) {
      await channel.invokeMethod<void>(folder ? 'openFolder' : 'open', {
        'path': path,
      });
    } else {
      final uri = Uri.file(
        folder ? p.dirname(path) : path,
        windows: Platform.isWindows,
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const AudioSourceException(
          'Nessuna applicazione disponibile per aprire il file o la cartella.',
        );
      }
    }
  }
}
