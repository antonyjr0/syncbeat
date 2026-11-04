// Standalone device probe. Build explicitly with -t audit/phone_youtube_search.dart.
// Uses the production provider/native bridge; no Spotify login or audio download.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';
import 'package:syncbeat/models/spotify_models.dart';

void main() => runApp(const MaterialApp(home: _SearchProbe()));

class _SearchProbe extends StatefulWidget {
  const _SearchProbe();
  @override
  State<_SearchProbe> createState() => _SearchProbeState();
}

class _SearchProbeState extends State<_SearchProbe> {
  bool _busy = false;
  int _attempt = 0;
  final _results = <String>[];
  DownloadCancellationToken? _cancellation;

  Future<void> _run() async {
    if (_busy) return;
    final cancellation = DownloadCancellationToken();
    _cancellation = cancellation;
    setState(() {
      _busy = true;
      _attempt++;
    });
    final timer = Stopwatch()..start();
    const track = SpotifyTrack(
      id: 'phone-search-probe',
      title: 'VELENO',
      artists: ['Tananai'],
      album: '',
      durationMs: 199000,
      isLocal: false,
    );
    try {
      final videos = await const YoutubeTools().search(track, cancellation);
      timer.stop();
      final ranked = const YoutubeMatcher().rank(track, videos);
      final evidence = {
        'attempt': _attempt,
        'elapsedMs': timer.elapsedMilliseconds,
        'results': videos.length,
        'firstId': ranked.first.video.id,
        'firstTitle': ranked.first.video.title,
        'audioDownloaded': false,
      };
      debugPrint('SYNCBEAT_SEARCH_PROBE ${jsonEncode(evidence)}');
      if (mounted) {
        setState(
          () => _results.add(
            'Prova $_attempt: ${(timer.elapsedMilliseconds / 1000).toStringAsFixed(2)} s, '
            '${videos.length} risultati. Primo: ${ranked.first.video.title}',
          ),
        );
      }
    } catch (error) {
      timer.stop();
      debugPrint(
        'SYNCBEAT_SEARCH_PROBE ${jsonEncode({'attempt': _attempt, 'elapsedMs': timer.elapsedMilliseconds, 'error': '$error'})}',
      );
      if (mounted) setState(() => _results.add('Errore: $error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verifica ricerca SyncBeat')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ricerca metadati: Tananai / VELENO. Nessun audio scaricato.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _run,
            child: const Text('Avvia prova'),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 20),
          for (final result in _results)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(result),
            ),
        ],
      ),
    ),
  );
}
