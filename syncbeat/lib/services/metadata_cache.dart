import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/spotify_models.dart';

abstract interface class MetadataStore {
  Future<List<SpotifyPlaylist>> readPlaylists();
  Future<void> writePlaylists(List<SpotifyPlaylist> playlists);
  Future<String?> readSelectedPlaylistId();
  Future<void> writeSelectedPlaylistId(String? playlistId);
  Future<List<SpotifyTrack>> readTracks();
  Future<void> writeTracks(List<SpotifyTrack> tracks);
}

class MetadataCache implements MetadataStore {
  MetadataCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _playlistsKey = 'spotify_playlists_v1';
  static const _selectedPlaylistKey = 'selected_playlist_id_v1';
  static const _tracksKey = 'spotify_tracks_v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<SpotifyPlaylist>> readPlaylists() async {
    final value = await _preferences.getString(_playlistsKey);
    if (value == null) return [];
    try {
      return (jsonDecode(value) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(SpotifyPlaylist.fromStoredJson)
          .toList(growable: false);
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  @override
  Future<void> writePlaylists(List<SpotifyPlaylist> playlists) =>
      _preferences.setString(
        _playlistsKey,
        jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
      );

  @override
  Future<String?> readSelectedPlaylistId() =>
      _preferences.getString(_selectedPlaylistKey);

  @override
  Future<void> writeSelectedPlaylistId(String? playlistId) async {
    if (playlistId == null) {
      await _preferences.remove(_selectedPlaylistKey);
    } else {
      await _preferences.setString(_selectedPlaylistKey, playlistId);
    }
  }

  @override
  Future<List<SpotifyTrack>> readTracks() async {
    final value = await _preferences.getString(_tracksKey);
    if (value == null) return [];
    try {
      return (jsonDecode(value) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(SpotifyTrack.fromStoredJson)
          .toList(growable: false);
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  @override
  Future<void> writeTracks(List<SpotifyTrack> tracks) => _preferences.setString(
    _tracksKey,
    jsonEncode(tracks.map((track) => track.toJson()).toList()),
  );
}
