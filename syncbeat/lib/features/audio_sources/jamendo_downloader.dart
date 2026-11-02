import 'dart:async';

import 'package:http/http.dart' as http;

import 'audio_source.dart';
import 'staging_storage.dart';

typedef JamendoRetryDelay = Future<void> Function(Duration duration);

class JamendoAudioDownloader implements AudioSourceDownloader {
  JamendoAudioDownloader({
    required this.stagingStorage,
    required this.offlineUseAuthorized,
    http.Client? httpClient,
    JamendoRetryDelay? retryDelay,
    this.maxRetries = 2,
    this.maxRedirects = 4,
  }) : _httpClient = httpClient ?? http.Client(),
       _retryDelay = retryDelay ?? _defaultRetryDelay;

  final AudioStagingStorage stagingStorage;
  final bool offlineUseAuthorized;
  final http.Client _httpClient;
  final JamendoRetryDelay _retryDelay;
  final int maxRetries;
  final int maxRedirects;

  static Future<void> _defaultRetryDelay(Duration duration) =>
      Future<void>.delayed(duration);

  @override
  String get id => 'jamendo';

  @override
  bool canDownload(AudioCandidate candidate) =>
      candidate.providerId == id &&
      candidate.isAuthorizedDownload &&
      offlineUseAuthorized &&
      _isAllowedDownloadHost(candidate.downloadUrl);

  @override
  Future<StagedAudioFile> download(
    AudioCandidate candidate, {
    required AudioDownloadProgress onProgress,
    required DownloadCancellationToken cancellationToken,
  }) async {
    if (!canDownload(candidate)) {
      throw AudioSourceException(
        candidate.license.restrictionReason ??
            'Il download Jamendo non è autorizzato per questo brano.',
        sourceId: id,
      );
    }
    final existing = await stagingStorage.findExistingCandidate(candidate);
    if (existing != null) return existing;
    var uri = candidate.downloadUrl!;
    for (
      var redirectCount = 0;
      redirectCount <= maxRedirects;
      redirectCount++
    ) {
      late http.StreamedResponse response;
      var attempts = 0;
      while (true) {
        cancellationToken.throwIfCancelled();
        final request =
            http.AbortableRequest(
                'GET',
                uri,
                abortTrigger: cancellationToken.whenCancelled,
              )
              ..followRedirects = false
              ..headers['Accept'] = 'audio/mpeg';
        try {
          response = await _httpClient
              .send(request)
              .timeout(const Duration(seconds: 30));
        } on http.RequestAbortedException {
          throw const DownloadCancelledException();
        } on Exception catch (error) {
          if (cancellationToken.isCancelled) {
            throw const DownloadCancelledException();
          }
          if (attempts >= maxRetries) {
            throw AudioSourceException(
              'Download Jamendo non riuscito: $error',
              sourceId: id,
            );
          }
          attempts++;
          await _retryDelay(Duration(seconds: attempts));
          continue;
        }
        if (response.statusCode < 500 || attempts >= maxRetries) break;
        await response.stream.drain<void>();
        attempts++;
        await _retryDelay(Duration(seconds: attempts));
      }

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || redirectCount == maxRedirects) {
          throw const AudioSourceException(
            'Redirect Jamendo non valido o troppi redirect.',
            sourceId: 'jamendo',
          );
        }
        final nextUri = uri.resolve(location);
        if (!_isAllowedDownloadHost(nextUri)) {
          throw const AudioSourceException(
            'Jamendo ha restituito un redirect verso un host non autorizzato.',
            sourceId: 'jamendo',
          );
        }
        uri = nextUri;
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw AudioSourceException(
          'Jamendo ha restituito HTTP ${response.statusCode} durante il download.',
          sourceId: id,
        );
      }

      return await stagingStorage.saveMp3(
        candidate: candidate,
        bytes: response.stream,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
        expectedBytes: response.contentLength,
      );
    }
    throw const AudioSourceException(
      'Download Jamendo interrotto per redirect non validi.',
      sourceId: 'jamendo',
    );
  }

  bool _isAllowedDownloadHost(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      (uri.host == 'api.jamendo.com' ||
          uri.host.endsWith('.storage.jamendo.com'));
}
