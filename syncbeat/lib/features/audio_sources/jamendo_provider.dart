import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../models/spotify_models.dart';
import 'audio_source.dart';

class JamendoProvider implements AudioSourceProvider {
  JamendoProvider({
    this.clientId = AppConfig.jamendoClientId,
    this.offlineUseAuthorized = AppConfig.jamendoOfflineUseAuthorized,
    http.Client? httpClient,
    this.durationSearchToleranceSeconds = 15,
  }) : _httpClient = httpClient ?? http.Client();

  final String clientId;
  final bool offlineUseAuthorized;
  final http.Client _httpClient;
  final int durationSearchToleranceSeconds;

  @override
  String get id => 'jamendo';

  @override
  String get displayName => 'Jamendo';

  bool get isConfigured => clientId.trim().isNotEmpty;

  @override
  Future<List<AudioCandidate>> search(SpotifyTrack track) async {
    if (!isConfigured) {
      throw const AudioSourceException(
        'Configura JAMENDO_CLIENT_ID tramite --dart-define per cercare su Jamendo.',
        sourceId: 'jamendo',
      );
    }
    final durationSeconds = track.durationMs ~/ 1000;
    final parameters = <String, String>{
      'client_id': clientId,
      'format': 'json',
      'limit': '50',
      'namesearch': track.title,
      'search': '${track.title} ${track.artistLine}',
      'include': 'licenses',
      'type': 'single albumtrack',
      'audiodlformat': 'mp32',
    };
    if (track.artists.isNotEmpty) {
      parameters['artist_name'] = track.artists.join(' ');
    }
    if (durationSeconds > 0) {
      final minimum = (durationSeconds - durationSearchToleranceSeconds).clamp(
        1,
        86400,
      );
      final maximum = durationSeconds + durationSearchToleranceSeconds;
      parameters['durationbetween'] = '${minimum}_$maximum';
    }

    final uri = Uri.https('api.jamendo.com', '/v3.0/tracks/', parameters);
    late final http.Response response;
    try {
      response = await _httpClient
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
    } on Exception catch (error) {
      throw AudioSourceException(
        'Ricerca Jamendo non riuscita: $error',
        sourceId: id,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AudioSourceException(
        'Jamendo ha restituito HTTP ${response.statusCode}.',
        sourceId: id,
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw const AudioSourceException(
        'Risposta Jamendo non valida.',
        sourceId: 'jamendo',
      );
    }
    final headers = payload['headers'] as Map<String, dynamic>?;
    if (headers?['status'] != 'success') {
      final message = headers?['error_message'] as String?;
      throw AudioSourceException(
        message == null || message.isEmpty
            ? 'Jamendo non ha completato la ricerca.'
            : message,
        sourceId: id,
      );
    }
    final results = payload['results'] as List<dynamic>? ?? const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(_candidateFromJson)
        .where((candidate) => candidate.title.isNotEmpty)
        .toList(growable: false);
  }

  AudioCandidate _candidateFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final allowedByJamendo = json['audiodownload_allowed'] == true;
    final downloadUrl = _safeJamendoUri(json['audiodownload'] as String?);
    final licenseUrl = _safeLicenseUri(json['license_ccurl'] as String?);
    final verifiedLicense =
        licenseUrl != null && _isSupportedLicense(licenseUrl);
    final sourceUrl =
        _safeJamendoUri(json['shareurl'] as String?) ??
        _safeJamendoUri(json['shorturl'] as String?);
    final canDownload = allowedByJamendo && downloadUrl != null;
    final license = AudioLicense(
      name: _licenseName(licenseUrl),
      url: licenseUrl,
      attribution: _attribution(json),
      verified: verifiedLicense,
      downloadPermission: canDownload && verifiedLicense,
      offlineUsePermission: offlineUseAuthorized,
      restrictionReason: !allowedByJamendo
          ? 'L’autore non ha autorizzato il download via API.'
          : !verifiedLicense
          ? 'Licenza Creative Commons assente o non riconosciuta.'
          : !offlineUseAuthorized
          ? 'Uso offline non abilitato: i Termini API Jamendo escludono l’accesso offline salvo autorizzazione esplicita.'
          : null,
    );
    final duration = json['duration'];
    return AudioCandidate(
      id: id,
      providerId: this.id,
      title: (json['name'] as String? ?? '').trim(),
      artist: (json['artist_name'] as String? ?? '').trim(),
      durationSeconds: duration is num ? duration.toInt() : 0,
      license: license,
      downloadUrl: canDownload ? downloadUrl : null,
      sourceUrl: sourceUrl,
      quality: 'MP3 VBR',
      estimatedFileSizeBytes: duration is num && duration > 0
          ? (duration.toInt() * 192000 / 8).ceil()
          : null,
      apiAllowsDownload: canDownload,
    );
  }

  Uri? _safeJamendoUri(String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https') return null;
    if (uri.host != 'jamendo.com' && !uri.host.endsWith('.jamendo.com')) {
      return null;
    }
    return uri;
  }

  Uri? _safeLicenseUri(String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host != 'creativecommons.org') {
      return null;
    }
    return uri.replace(scheme: 'https');
  }

  bool _isSupportedLicense(Uri uri) => RegExp(
    r'^/licenses/(by|by-sa|by-nd|by-nc|by-nc-sa|by-nc-nd)/[0-9.]+/?$',
  ).hasMatch(uri.path);

  String _licenseName(Uri? uri) {
    if (uri == null) return 'Licenza non verificata';
    final match = RegExp(r'^/licenses/([^/]+)/([0-9.]+)').firstMatch(uri.path);
    if (match == null || !_isSupportedLicense(uri)) {
      return 'Licenza Creative Commons non riconosciuta';
    }
    return 'CC ${match.group(1)!.toUpperCase()} ${match.group(2)}';
  }

  String? _attribution(Map<String, dynamic> json) {
    final artist = json['artist_name'] as String?;
    final shareUrl = _safeJamendoUri(json['shareurl'] as String?);
    if (artist == null || shareUrl == null) return null;
    return '$artist · ${shareUrl.toString()} · Jamendo';
  }
}
