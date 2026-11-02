import 'package:diacritic/diacritic.dart';

import '../../models/spotify_models.dart';
import 'audio_source.dart';

class TrackMatcher {
  const TrackMatcher({
    this.minimumConfidence = 0.58,
    this.confidentMatchThreshold = 0.86,
    this.ambiguityMargin = 0.08,
    this.durationToleranceSeconds = 10,
  });

  final double minimumConfidence;
  final double confidentMatchThreshold;
  final double ambiguityMargin;
  final int durationToleranceSeconds;

  static const _versionMarkers = {
    'acoustic',
    'karaoke',
    'live',
    'demo',
    'cover',
    'remix',
    'edit',
    'instrumental',
    'radio',
    'extended',
    'sped',
    'slowed',
    'nightcore',
    'mono',
    'stereo',
    'clean',
    'explicit',
  };

  static String normalize(String value) => removeDiacritics(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  AudioMatchResult match(
    SpotifyTrack track,
    Iterable<AudioCandidate> candidates,
  ) {
    final ranked = <ScoredAudioCandidate>[];
    final trackTitle = normalize(track.title);
    final trackArtists = track.artists
        .map(normalize)
        .where((item) => item.isNotEmpty);
    final trackDuration = track.durationMs / 1000;

    for (final candidate in candidates) {
      final candidateTitle = normalize(candidate.title);
      final candidateArtist = normalize(candidate.artist);
      if (candidateTitle.isEmpty || candidateArtist.isEmpty) continue;
      if (!_sameVersion(trackTitle, candidateTitle)) continue;

      final titleScore = _stringSimilarity(trackTitle, candidateTitle);
      final artistScore = trackArtists
          .map((artist) => _stringSimilarity(artist, candidateArtist))
          .fold<double>(0, (best, score) => score > best ? score : best);
      final durationDifference = (trackDuration - candidate.durationSeconds)
          .abs();
      if (trackDuration > 0 &&
          candidate.durationSeconds > 0 &&
          durationDifference > durationToleranceSeconds) {
        continue;
      }
      final durationScore = trackDuration <= 0 || candidate.durationSeconds <= 0
          ? 0.5
          : 1 - durationDifference / durationToleranceSeconds;
      final confidence =
          (titleScore * 0.55 + artistScore * 0.35 + durationScore * 0.1)
              .clamp(0, 1)
              .toDouble();
      if (confidence >= minimumConfidence) {
        ranked.add(
          ScoredAudioCandidate(
            candidate: candidate
                .withConfidence(confidence)
                .forSpotifyTrack(track),
            confidence: confidence,
          ),
        );
      }
    }

    ranked.sort((left, right) => right.confidence.compareTo(left.confidence));
    if (ranked.isEmpty) {
      return AudioMatchResult(
        track: track,
        candidates: const [],
        status: TrackMatchStatus.noMatch,
      );
    }

    final topScore = ranked.first.confidence;
    final runnerUpScore = ranked.length > 1 ? ranked[1].confidence : 0.0;
    final confident =
        topScore >= confidentMatchThreshold &&
        topScore - runnerUpScore >= ambiguityMargin;
    return AudioMatchResult(
      track: track,
      candidates: List.unmodifiable(ranked),
      status: confident
          ? TrackMatchStatus.confident
          : TrackMatchStatus.manualSelectionRequired,
    );
  }

  bool _sameVersion(String left, String right) {
    Set<String> markers(String title) => title
        .split(' ')
        .where(
          (word) =>
              _versionMarkers.contains(word) || word.startsWith('remaster'),
        )
        .toSet();

    final leftMarkers = markers(left);
    final rightMarkers = markers(right);
    return leftMarkers.containsAll(rightMarkers) &&
        rightMarkers.containsAll(leftMarkers);
  }

  double _stringSimilarity(String left, String right) {
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;

    final leftTokens = left.split(' ').toSet();
    final rightTokens = right.split(' ').toSet();
    final overlap = leftTokens.intersection(rightTokens).length;
    final tokenScore = 2 * overlap / (leftTokens.length + rightTokens.length);
    final editScore = _editSimilarity(left, right);
    return (tokenScore * 0.35 + editScore * 0.65).clamp(0, 1).toDouble();
  }

  double _editSimilarity(String left, String right) {
    var shorter = left;
    var longer = right;
    if (shorter.length > longer.length) {
      shorter = right;
      longer = left;
    }
    if (shorter.isEmpty) return 0;

    var previous = List<int>.generate(shorter.length + 1, (index) => index);
    for (var row = 1; row <= longer.length; row++) {
      final current = List<int>.filled(shorter.length + 1, 0);
      current[0] = row;
      for (var column = 1; column <= shorter.length; column++) {
        final substitutionCost =
            longer.codeUnitAt(row - 1) == shorter.codeUnitAt(column - 1)
            ? 0
            : 1;
        current[column] = [
          current[column - 1] + 1,
          previous[column] + 1,
          previous[column - 1] + substitutionCost,
        ].reduce((left, right) => left < right ? left : right);
      }
      previous = current;
    }
    return 1 - previous.last / longer.length;
  }
}
