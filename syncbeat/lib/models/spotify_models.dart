class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.owner,
    required this.trackCount,
    this.imageUrl,
    this.description = '',
  });

  final String id;
  final String name;
  final String owner;
  final int trackCount;
  final String? imageUrl;
  final String description;

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as List<dynamic>? ?? const [];
    final owner = json['owner'] as Map<String, dynamic>?;
    final items = json['items'] as Map<String, dynamic>?;
    final tracks = json['tracks'] as Map<String, dynamic>?;
    return SpotifyPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Playlist senza nome',
      owner: owner?['display_name'] as String? ?? 'Utente Spotify',
      trackCount:
          (items?['total'] as num?)?.toInt() ??
          (tracks?['total'] as num?)?.toInt() ??
          0,
      imageUrl: images.isEmpty
          ? null
          : (images.first as Map<String, dynamic>)['url'] as String?,
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'owner': owner,
    'trackCount': trackCount,
    'imageUrl': imageUrl,
    'description': description,
  };

  factory SpotifyPlaylist.fromStoredJson(Map<String, dynamic> json) =>
      SpotifyPlaylist(
        id: json['id'] as String,
        name: json['name'] as String,
        owner: json['owner'] as String? ?? 'Utente Spotify',
        trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
        imageUrl: json['imageUrl'] as String?,
        description: json['description'] as String? ?? '',
      );
}

class SpotifyTrack {
  const SpotifyTrack({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    required this.durationMs,
    required this.isLocal,
    this.imageUrl,
    this.spotifyUrl,
  });

  final String id;
  final String title;
  final List<String> artists;
  final String album;
  final int durationMs;
  final bool isLocal;
  final String? imageUrl;
  final String? spotifyUrl;

  factory SpotifyTrack.fromJson(
    Map<String, dynamic> json, {
    bool isLocal = false,
  }) {
    final album = json['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>? ?? const [];
    final artists = json['artists'] as List<dynamic>? ?? const [];
    final externalUrls = json['external_urls'] as Map<String, dynamic>?;
    return SpotifyTrack(
      id: json['id'] as String? ?? '',
      title: json['name'] as String? ?? 'Brano senza titolo',
      artists: artists
          .whereType<Map<String, dynamic>>()
          .map((artist) => artist['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false),
      album: album?['name'] as String? ?? '',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      isLocal: isLocal,
      imageUrl: images.isEmpty
          ? null
          : (images.first as Map<String, dynamic>)['url'] as String?,
      spotifyUrl: externalUrls?['spotify'] as String?,
    );
  }

  String get artistLine =>
      artists.isEmpty ? 'Artista sconosciuto' : artists.join(', ');

  Map<String, Object?> toJson() => {
    'id': id,
    'name': title,
    'artists': artists.map((name) => {'name': name}).toList(),
    'album': {
      'name': album,
      'images': imageUrl == null
          ? []
          : [
              {'url': imageUrl},
            ],
    },
    'duration_ms': durationMs,
    'is_local': isLocal,
    'external_urls': spotifyUrl == null ? {} : {'spotify': spotifyUrl},
  };

  factory SpotifyTrack.fromStoredJson(Map<String, dynamic> json) =>
      SpotifyTrack.fromJson(json, isLocal: json['is_local'] as bool? ?? false);
}

class TrackImportResult {
  const TrackImportResult({required this.trackId, this.track, this.error});

  final String trackId;
  final SpotifyTrack? track;
  final String? error;
}
