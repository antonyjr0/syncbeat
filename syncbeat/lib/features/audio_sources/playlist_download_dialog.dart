import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/spotify_models.dart';
import '../zepp/zepp_download_transfer.dart';
import '../zepp/zepp_transfer_dialog.dart';
import 'audio_match_dialog.dart';
import 'audio_source.dart';
import 'local_mp3_provider.dart';
import 'public_audio_storage.dart';
import 'youtube_downloader.dart';
import 'youtube_match_dialog.dart';
import 'youtube_provider.dart';

class PlaylistDownloadDialog extends StatefulWidget {
  const PlaylistDownloadDialog({
    required this.name,
    required this.tracks,
    super.key,
  });

  final String name;
  final List<SpotifyTrack> tracks;

  @override
  State<PlaylistDownloadDialog> createState() => _PlaylistDownloadDialogState();
}

class _PlaylistDownloadDialogState extends State<PlaylistDownloadDialog> {
  final _storage = PublicAudioStorage();
  final _associations = YoutubeAssociations();
  final _transfer = ZeppDownloadTransfer();
  static const _tools = YoutubeTools();
  late final _local = LocalMp3Provider(stagingStorage: _storage);
  late final _youtube = YoutubeDownloader(tools: _tools, storage: _storage);
  late final _tracks = {
    for (final track in widget.tracks) track.id: track,
  }.values.toList();
  final _files = <String, PublishedAudio>{};
  final _messages = <String, String>{};
  final _suggestions = <String, List<RankedYoutubeVideo>>{};
  final _sent = <String>{};
  DownloadCancellationToken? _token;
  bool _sending = false;
  bool _stopSending = false;
  String? _activity;
  String? _error;

  bool get _busy => _token != null || _sending;

  @override
  void initState() {
    super.initState();
    unawaited(_download());
  }

  @override
  void dispose() {
    _token?.cancel();
    if (_sending) unawaited(_transfer.cancel());
    super.dispose();
  }

  Future<void> _download() async {
    final token = DownloadCancellationToken();
    setState(() {
      _token = token;
      _error = null;
      _activity = 'Controllo dei brani già salvati…';
    });
    try {
      final saved = await _storage.filesForSpotifyTracks(
        _tracks.map((track) => track.id).toSet(),
      );
      token.throwIfCancelled();
      if (!mounted) return;
      setState(() => _files.addAll(saved));
      for (final (index, track) in _tracks.indexed) {
        token.throwIfCancelled();
        if (_files.containsKey(track.id)) continue;
        if (track.isLocal) {
          setState(() => _messages[track.id] = 'Da verificare manualmente');
          continue;
        }
        setState(
          () => _activity = '${index + 1}/${_tracks.length} · ${track.title}',
        );
        try {
          final video = await _associations.read(track.id);
          token.throwIfCancelled();
          if (video == null) {
            final results =
                _suggestions[track.id] ??
                await searchYoutubeMatches(
                  track: track,
                  tools: _tools,
                  matcher: const YoutubeMatcher(),
                  token: token,
                );
            token.throwIfCancelled();
            setState(() {
              _suggestions[track.id] = results;
              _messages[track.id] = results.isEmpty
                  ? 'Nessuna corrispondenza trovata'
                  : '${results.length} risultati YouTube · scegli e autorizza';
            });
            continue;
          }
          final authorization = YoutubeAssociations.authorizationFor(video);
          if (!authorization.valid) {
            setState(
              () => _messages[track.id] = 'Autorizzazione da verificare',
            );
            continue;
          }
          final file = await _youtube.download(
            track: track,
            video: video,
            authorization: authorization,
            cancellation: token,
            onProgress: (_) {},
          );
          if (!mounted) return;
          setState(
            () => _files[track.id] = PublishedAudio(file.path, file.fileName),
          );
        } on DownloadCancelledException {
          rethrow;
        } on Exception catch (error) {
          if (!mounted) return;
          setState(
            () => _messages[track.id] = 'Download non riuscito · $error',
          );
        }
      }
    } on DownloadCancelledException {
      if (mounted) {
        setState(
          () => _error =
              'Download interrotto. I brani salvati restano disponibili.',
        );
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _token = null;
          _activity = null;
        });
      }
    }
  }

  Future<void> _review(SpotifyTrack track) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AudioMatchDialog(
        track: track,
        localProvider: _local,
        downloadManager: AudioDownloadManager([_local]),
        showJamendo: false,
        allowWatchTransfer: false,
        playlistSuggestions: _suggestions[track.id] ?? const [],
      ),
    );
    if (!mounted) return;
    try {
      final saved = await _storage.filesForSpotifyTracks({track.id});
      final video = await _associations.read(track.id);
      if (mounted) {
        setState(() {
          _files.addAll(saved);
          if (video != null &&
              YoutubeAssociations.authorizationFor(video).valid) {
            _messages[track.id] = 'Pronto per il download';
          }
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _stopSending = false;
      _error = null;
    });
    SpotifyTrack? current;
    try {
      for (final track in _tracks) {
        final file = _files[track.id];
        if (file == null || _sent.contains(track.id)) continue;
        if (!mounted || _stopSending) break;
        current = track;
        setState(() => _activity = 'Invio · ${track.title}');
        await _transfer.send(
          file,
          title: track.title,
          artist: track.artistLine,
          onEvent: (_) {},
        );
        if (mounted) setState(() => _sent.add(track.id));
      }
    } on ZeppDownloadSetupRequired catch (error) {
      final file = _files[current?.id];
      if (mounted && file != null && !_stopSending) {
        final configured = await showWatchDownloadSetup(context, file);
        if (mounted && configured) return;
      }
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = '${current?.title ?? 'Invio'} · $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _activity = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.name),
      content: SizedBox(
        width: 550,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_files.length}/${_tracks.length} brani salvati'
              '${_sent.isEmpty ? '' : ' · ${_sent.length} inviati'}',
            ),
            if (_files.length < _tracks.length)
              const Text(
                'SyncBeat cerca i brani mancanti e scarica quelli già autorizzati. Usa Rivedi per confermare i risultati, poi Scarica brani autorizzati.',
              ),
            if (_activity case final activity?) ...[
              const LinearProgressIndicator(),
              Text(activity),
            ],
            if (_error case final error?) Text(error),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tracks.length,
                itemBuilder: (context, index) {
                  final track = _tracks[index];
                  final saved = _files.containsKey(track.id);
                  return ListTile(
                    title: Text(track.title),
                    subtitle: Text(
                      '${track.artistLine}\n${_sent.contains(track.id)
                          ? 'Inviato'
                          : saved
                          ? 'Salvato'
                          : _messages[track.id] ?? (_busy ? 'In attesa' : 'Da rivedere')}',
                    ),
                    trailing: !_busy && !saved
                        ? TextButton(
                            onPressed: () => _review(track),
                            child: const Text('Rivedi'),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_busy)
          TextButton(
            onPressed: () {
              if (_sending) {
                setState(() => _stopSending = true);
              } else {
                _token?.cancel();
              }
            },
            child: Text(
              _sending ? 'Ferma dopo questo brano' : 'Interrompi download',
            ),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
          if (_files.length < _tracks.length)
            TextButton(
              onPressed: _download,
              child: const Text('Scarica brani autorizzati'),
            ),
          if (defaultTargetPlatform == TargetPlatform.android &&
              _files.length > _sent.length)
            FilledButton(
              onPressed: _send,
              child: Text(
                _files.length == _tracks.length
                    ? 'Invia playlist all’orologio'
                    : 'Invia i brani salvati',
              ),
            ),
        ],
      ],
    ),
  );
}
