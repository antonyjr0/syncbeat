import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_source.dart';
import 'youtube_models.dart';
import 'youtube_downloader.dart';

class YoutubeAssociations {
  // Shared across repository instances: read/modify/write must not race with
  // a replacement selection or a revocation from another dialog.
  static final _writes = <String, Future<void>>{};

  Future<void> _serialize(String spotifyId, Future<void> Function() write) {
    final previous = _writes[spotifyId] ?? Future<void>.value();
    final result = previous.then((_) => write());
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _writes[spotifyId] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_writes[spotifyId], settled)) _writes.remove(spotifyId);
      }),
    );
    return result;
  }

  static String key(String spotifyId) => 'youtube.selection.v1.$spotifyId';
  Future<YoutubeVideo?> read(String spotifyId) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(key(spotifyId));
      if (raw == null) return null;
      final video = YoutubeVideo(jsonDecode(raw) as Map<String, dynamic>);
      // Validate lazy getters here, before bad persisted values reach widgets.
      video.title;
      video.channel;
      video.channelId;
      video.duration;
      video.thumbnail;
      return video;
    } on FormatException {
      throw const AudioSourceException(
        'Associazione YouTube salvata non leggibile. Cerca e salva una nuova scelta.',
      );
    } on TypeError {
      throw const AudioSourceException(
        'Associazione YouTube salvata non leggibile. Cerca e salva una nuova scelta.',
      );
    }
  }

  Future<void> save(
    String spotifyId,
    YoutubeVideo video, {
    YoutubeDownloadAuthorization? authorization,
  }) => _serialize(spotifyId, () async {
    if (spotifyId.isEmpty) {
      throw const AudioSourceException('Spotify ID mancante.');
    }
    YoutubeVideo? previous;
    try {
      previous = await read(spotifyId);
    } on AudioSourceException {
      // An explicit new selection repairs an unreadable old record.
    }
    final approval = previous?.id == video.id
        ? previous?.metadata['downloadApproval']
        : null;
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setString(
      key(spotifyId),
      jsonEncode({
        'id': video.id,
        'title': video.title,
        'channel': video.channel,
        'channel_id': video.channelId,
        'channel_is_verified': video.metadata['channel_is_verified'],
        'duration': video.duration,
        'thumbnail': video.thumbnail,
        'selectedAt': DateTime.now().toUtc().toIso8601String(),
        'downloadApproval': ?(authorization == null
            ? approval
            : _approval(video.id, authorization)),
      }),
    );
    if (!stored) {
      throw const AudioSourceException(
        'Impossibile salvare la scelta YouTube.',
      );
    }
  });

  static YoutubeDownloadAuthorization authorizationFor(YoutubeVideo video) {
    final data = video.metadata['downloadApproval'];
    if (data is! Map || data['version'] != 1 || data['videoId'] != video.id) {
      return const YoutubeDownloadAuthorization(
        rightsAndPlatformPermission: false,
        conversionAndOfflineUse: false,
      );
    }
    return YoutubeDownloadAuthorization(
      rightsAndPlatformPermission: data['rights'] == true,
      conversionAndOfflineUse: data['conversion'] == true,
    );
  }

  Future<void> saveAuthorization(
    String spotifyId,
    String videoId,
    YoutubeDownloadAuthorization authorization,
  ) => _serialize(spotifyId, () async {
    final saved = await read(spotifyId);
    if (saved == null || saved.id != videoId) {
      throw const AudioSourceException('Salva prima questa associazione.');
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setString(
      key(spotifyId),
      jsonEncode({
        ...saved.metadata,
        'downloadApproval': _approval(videoId, authorization),
      }),
    );
    if (!stored) {
      throw const AudioSourceException('Impossibile salvare le conferme.');
    }
  });

  static Map<String, dynamic> _approval(
    String videoId,
    YoutubeDownloadAuthorization authorization,
  ) => {
    'version': 1,
    'videoId': videoId,
    'rights': authorization.rightsAndPlatformPermission,
    'conversion': authorization.conversionAndOfflineUse,
    'confirmedAt': DateTime.now().toUtc().toIso8601String(),
  };
}
