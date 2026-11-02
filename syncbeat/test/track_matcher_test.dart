import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/track_matcher.dart';
import 'package:syncbeat/models/spotify_models.dart';

void main() {
  const matcher = TrackMatcher();

  test('normalizes accents, punctuation and repeated whitespace', () {
    expect(TrackMatcher.normalize('  Café—Noir!  '), 'cafe noir');
  });

  test('scores title, artist and duration and returns confident match', () {
    final result = matcher.match(_spotifyTrack(), [_candidate()]);

    expect(result.status, TrackMatchStatus.confident);
    expect(result.candidates.single.confidence, greaterThan(0.9));
  });

  test('rejects candidates outside the configured duration tolerance', () {
    final result = matcher.match(_spotifyTrack(), [
      _candidate(durationSeconds: 240),
    ]);

    expect(result.status, TrackMatchStatus.noMatch);
    expect(result.candidates, isEmpty);
  });

  test('does not silently match live/remix versions to studio versions', () {
    final result = matcher.match(_spotifyTrack(), [
      _candidate(title: 'Northern Lights - Live'),
      _candidate(title: 'Northern Lights Remix'),
    ]);

    expect(result.status, TrackMatchStatus.noMatch);
  });

  test('marks tied results for explicit user selection', () {
    final result = matcher.match(_spotifyTrack(), [
      _candidate(id: 'jamendo:1'),
      _candidate(id: 'jamendo:2'),
    ]);

    expect(result.status, TrackMatchStatus.manualSelectionRequired);
    expect(result.requiresManualSelection, isTrue);
  });
}

SpotifyTrack _spotifyTrack() => const SpotifyTrack(
  id: 'spotify-1',
  title: 'Northern Lights',
  artists: ['Elena Sol'],
  album: 'Skyline',
  durationMs: 180000,
  isLocal: false,
);

AudioCandidate _candidate({
  String id = 'jamendo:1',
  String title = 'Northern Lights',
  String artist = 'Eléna Sol',
  int durationSeconds = 181,
}) => AudioCandidate(
  id: id,
  providerId: 'jamendo',
  title: title,
  artist: artist,
  durationSeconds: durationSeconds,
  license: const AudioLicense(name: 'Creative Commons BY'),
);
