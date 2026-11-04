import '../../models/spotify_models.dart';
import 'track_matcher.dart';
import 'youtube_channels.dart';
import 'youtube_models.dart';

class YoutubeMatchWeights {
  const YoutubeMatchWeights({
    this.title = 35,
    this.artist = 25,
    this.duration = 20,
    this.version = 12,
    this.provenance = 6,
    this.verification = 2,
  });
  final double title, artist, duration, version, provenance, verification;
  double get total =>
      title + artist + duration + version + provenance + verification;
  bool get valid =>
      [
        title,
        artist,
        duration,
        version,
        provenance,
        verification,
      ].every((w) => w.isFinite && w >= 0) &&
      total > 0;
}

class RankedYoutubeVideo {
  const RankedYoutubeVideo(
    this.video,
    this.score, {
    this.reasons = const [],
    this.durationDifference,
    this.ambiguous = false,
  });
  final YoutubeVideo video;

  /// Normalized score, 0–100 (not a probability).
  final double score;
  final List<String> reasons;
  final double? durationDifference;
  final bool ambiguous;
}

class YoutubeMatcher {
  const YoutubeMatcher({
    this.weights = const YoutubeMatchWeights(),
    this.ambiguityMargin = 3,
    this.durationTolerance = 30,
  });
  final YoutubeMatchWeights weights;
  final double ambiguityMargin;
  final double durationTolerance;

  static Set<String> _words(String s) =>
      TrackMatcher.normalize(s).split(' ').where((s) => s.isNotEmpty).toSet();
  static double _coverage(String expected, String actual) {
    final a = _words(expected), b = _words(actual);
    return a.isEmpty || b.isEmpty ? 0 : a.intersection(b).length / a.length;
  }

  static const _markers = [
    'live',
    'remix',
    'cover',
    'karaoke',
    'instrumental',
    'sped up',
    'spedup',
    'slowed',
    'nightcore',
    'acoustic',
    'demo',
    'extended',
    'radio edit',
    'remaster',
  ];
  static Set<String> _versions(String title) {
    final normalized = TrackMatcher.normalize(
      title,
    ).replaceAll(RegExp(r'\bremastered\b'), 'remaster');
    return _markers
        .where((m) => RegExp('(^| )$m( |\$)').hasMatch(normalized))
        .map((m) => m == 'spedup' ? 'sped up' : m)
        .toSet();
  }

  static String _coreTitle(String value, List<String> artists) {
    var text = TrackMatcher.normalize(value);
    for (final artist in artists) {
      final name = TrackMatcher.normalize(artist);
      if (name.isNotEmpty) {
        text = text.replaceAll(
          RegExp('(^| )${RegExp.escape(name)}(?= |\$)'),
          ' ',
        );
      }
    }
    text = text.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ');
    text = text.replaceAll(
      RegExp(
        r'\b(official music video|official video|official audio|lyric video|lyrics video|music video)\b',
      ),
      ' ',
    );
    final original = text;
    for (final marker in [
      ..._markers,
      'remastered',
      'official',
      'lyrics',
      'lyric',
      'hd',
      'hq',
      'visualizer',
    ]) {
      text = text.replaceAll(RegExp('(^| )$marker(?= |\$)'), ' ');
    }
    return text.trim().isEmpty ? original : text;
  }

  List<RankedYoutubeVideo> rank(
    SpotifyTrack track,
    Iterable<YoutubeVideo> videos,
  ) {
    if (!weights.valid ||
        durationTolerance <= 0 ||
        !durationTolerance.isFinite ||
        ambiguityMargin < 0) {
      throw ArgumentError('Pesi o tolleranze di matching non validi');
    }
    final requestedVersions = _versions(track.title);
    final ranked = videos.map((video) {
      final info =
          video.channelInfo ??
          const YoutubeChannelClassifier().classify(video.metadata);
      final meta = video.metadata;
      final expectedTitle = _words(_coreTitle(track.title, track.artists));
      final actualTitle = _words(
        _coreTitle(meta['track'] as String? ?? video.title, track.artists),
      );
      final title = expectedTitle.isEmpty || actualTitle.isEmpty
          ? 0.0
          : 2 *
                expectedTitle.intersection(actualTitle).length /
                (expectedTitle.length + actualTitle.length);
      final artistText =
          '${meta['artists'] is List ? (meta['artists'] as List).join(' ') : ''} ${meta['artist'] ?? ''} ${video.title} ${video.channel}';
      // Every collaborator contributes; matching only the lead is insufficient.
      final artists = track.artists.where((a) => a.trim().isNotEmpty).toList();
      final artist = artists.isEmpty
          ? 0.0
          : artists
                    .map((a) => _coverage(a, artistText))
                    .reduce((a, b) => a + b) /
                artists.length;
      final difference = track.durationMs > 0 && video.duration > 0
          ? video.duration - track.durationMs / 1000
          : null;
      final duration = difference == null
          ? 0.0
          : (1 - difference.abs() / durationTolerance).clamp(0.0, 1.0);
      final versions = _versions(video.title);
      final unexpected = versions.difference(requestedVersions);
      final missing = requestedVersions.difference(versions);
      final version =
          video.title.trim().isEmpty ||
              unexpected.isNotEmpty ||
              missing.isNotEmpty
          ? 0.0
          : 1.0;
      final description = meta['description'] as String? ?? '';
      final provided = RegExp(
        r'Provided to YouTube by',
        caseSensitive: false,
      ).hasMatch(description);
      final officialText = RegExp(
        r'official (audio|video|music video)',
        caseSensitive: false,
      ).hasMatch(video.title);
      final provenance = info.oac == OacStatus.confirmed
          ? 1.0
          : info.isTopic
          ? .9
          : info.isLabel
          ? .8
          : provided
          ? .4
          : officialText
          ? .15
          : 0.0;
      final verification = info.verification == ChannelVerification.verified
          ? 1.0
          : 0.0;
      var score =
          (title * weights.title +
              artist * weights.artist +
              duration * weights.duration +
              version * weights.version +
              provenance * weights.provenance +
              verification * weights.verification) /
          weights.total *
          100;
      // Version mismatch must outweigh small badge/provenance bonuses.
      score -= (unexpected.length * 18 + missing.length * 12);
      if (title < .5 || artist < .5) score = score.clamp(0, 45);
      if (difference != null && difference.abs() > durationTolerance) {
        score = score.clamp(0, 60);
      }
      return RankedYoutubeVideo(
        video.withChannelInfo(info),
        score.clamp(0.0, 100.0),
        durationDifference: difference,
        reasons: [
          'Titolo ${(title * 100).round()}% · Artisti/collaborazioni ${(artist * 100).round()}%',
          difference == null
              ? 'Durata mancante: nessun punto durata'
              : 'Differenza durata ${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(1)} s',
          if (unexpected.isNotEmpty)
            'Varianti non richieste: ${unexpected.join(', ')}',
          if (missing.isNotEmpty)
            'Versione richiesta non riscontrata: ${missing.join(', ')}',
          if (version == 1) 'Versione compatibile con i metadati disponibili',
          if (info.oac == OacStatus.confirmed)
            'OAC confermato da evidenza indipendente',
          if (info.isTopic) 'Provenienza Topic: nessuna penalità automatica',
          if (info.isLabel)
            'Etichetta/distributore identificato tramite channel_id',
          if (provided)
            'Metadati Provided to YouTube (indizio di distribuzione)',
          if (officialText)
            'Dicitura Official Audio/Video: indizio debole, non prova OAC',
          if (verification == 1)
            'Verifica generica: peso limitato, non prova OAC',
          ...info.reasons,
        ],
      );
    }).toList();
    ranked.sort((a, b) {
      final order = b.score.compareTo(a.score);
      return order != 0 ? order : a.video.id.compareTo(b.video.id);
    });
    if (ranked.length > 1 &&
        ranked.first.score - ranked[1].score <= ambiguityMargin) {
      for (var i = 0; i < ranked.length; i++) {
        if (ranked.first.score - ranked[i].score > ambiguityMargin) break;
        final r = ranked[i];
        ranked[i] = RankedYoutubeVideo(
          r.video,
          r.score,
          reasons: r.reasons,
          durationDifference: r.durationDifference,
          ambiguous: true,
        );
      }
    }
    return ranked;
  }
}
