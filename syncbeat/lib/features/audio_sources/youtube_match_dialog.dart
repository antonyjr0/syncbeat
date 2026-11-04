import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'android_youtube_bridge.dart';

import '../../models/spotify_models.dart';
import 'audio_source.dart';
import 'staging_storage.dart';
import 'public_audio_storage.dart';
import 'youtube_downloader.dart';
import 'youtube_provider.dart';
import 'youtube_channels.dart';

class YoutubeMatchDialog extends StatefulWidget {
  const YoutubeMatchDialog({
    required this.track,
    this.tools = const YoutubeTools(),
    this.associations,
    this.channelCache,
    this.matcher = const YoutubeMatcher(),
    this.storage,
    this.downloader,
    super.key,
  });
  final SpotifyTrack track;
  final YoutubeTools tools;
  final YoutubeAssociations? associations;
  final YoutubeChannelCache? channelCache;
  final YoutubeMatcher matcher;
  final AudioStagingStorage? storage;
  final YoutubeDownloader? downloader;
  @override
  State<YoutubeMatchDialog> createState() => _YoutubeMatchDialogState();
}

class _YoutubeMatchDialogState extends State<YoutubeMatchDialog> {
  late final YoutubeAssociations _associations =
      widget.associations ?? YoutubeAssociations();
  List<RankedYoutubeVideo> _results = [];
  YoutubeVideo? _saved;
  YoutubeVideo? _selected;
  DownloadCancellationToken? _operation = DownloadCancellationToken();
  DownloadProgress? _progress;
  bool _rights = false;
  bool _conversion = false;
  String? _message;
  String _phase = 'Caricamento associazione';
  StagedAudioFile? _downloaded;
  final _selectionPanel = GlobalKey();
  final _statusPanel = GlobalKey();

  void _revealStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final panel = _statusPanel.currentContext;
      if (panel != null) {
        Scrollable.ensureVisible(panel, alignment: 0.1);
      }
    });
  }

  void _choose(YoutubeVideo? video) {
    setState(() {
      _selected = video;
      _downloaded = null;
      final approval = video?.id == _saved?.id && _saved != null
          ? YoutubeAssociations.authorizationFor(_saved!)
          : null;
      _rights = approval?.rightsAndPlatformPermission ?? false;
      _conversion = approval?.conversionAndOfflineUse ?? false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panel = _selectionPanel.currentContext;
      if (panel != null) {
        Scrollable.ensureVisible(
          panel,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await _associations.read(widget.track.id);
      if (mounted) {
        setState(() {
          _saved = saved;
          _selected = saved;
          if (saved != null) {
            final approval = YoutubeAssociations.authorizationFor(saved);
            _rights = approval.rightsAndPlatformPermission;
            _conversion = approval.conversionAndOfflineUse;
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  @override
  void dispose() {
    _operation?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    final token = DownloadCancellationToken();
    setState(() {
      _operation = token;
      _message = null;
      _selected = null;
      _results = [];
      _progress = null;
      _phase = 'Ricerca YouTube';
    });
    try {
      final videos = await widget.tools.search(widget.track, token);
      final cache = widget.channelCache ?? YoutubeChannelCache.shared;
      final enriched = await Future.wait(
        videos.map((video) async {
          final evidence = video.channelId == null
              ? null
              : await cache.lookup(video.channelId!);
          return video.withChannelInfo(
            const YoutubeChannelClassifier().classify(
              video.metadata,
              evidence: evidence,
            ),
          );
        }),
      );
      token.throwIfCancelled();
      if (mounted) {
        setState(
          () => _results = widget.matcher
              .rank(widget.track, enriched)
              .take(10)
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _updateAndroidEngine() async {
    final token = DownloadCancellationToken();
    setState(() {
      _operation = token;
      _message = 'Aggiornamento del motore YouTube…';
    });
    try {
      await AndroidYoutubeBridge().run(
        ['--syncbeat-update-engine'],
        cancellation: token,
        onLine: (_) {},
        timeout: const Duration(minutes: 3),
      );
      if (mounted) {
        setState(
          () => _message = 'Motore aggiornato. Puoi ripetere la ricerca.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _save() async {
    final video = _selected;
    if (video == null || _operation != null) return;
    final authorization = _authorization;
    setState(() {
      _operation = DownloadCancellationToken();
      _phase = 'Salvataggio associazione';
    });
    try {
      await _associations.save(
        widget.track.id,
        video,
        authorization: authorization,
      );
      final saved = await _associations.read(widget.track.id);
      if (mounted) {
        setState(() {
          _saved = saved;
          _message = 'Associazione salvata.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _open(YoutubeVideo video) async {
    try {
      if (!await launchUrl(video.url, mode: LaunchMode.externalApplication)) {
        throw const AudioSourceException('Impossibile aprire il browser.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  YoutubeDownloadAuthorization get _authorization =>
      YoutubeDownloadAuthorization(
        rightsAndPlatformPermission: _rights,
        conversionAndOfflineUse: _conversion,
      );
  Future<void> _changeApproval({bool? rights, bool? conversion}) async {
    if (_operation != null) return;
    final video = _selected;
    final oldRights = _rights;
    final oldConversion = _conversion;
    setState(() {
      _rights = rights ?? _rights;
      _conversion = conversion ?? _conversion;
    });
    if (video == null || video.id != _saved?.id) return;
    setState(() => _operation = DownloadCancellationToken());
    try {
      await _associations.saveAuthorization(
        widget.track.id,
        video.id,
        _authorization,
      );
      final saved = await _associations.read(widget.track.id);
      if (mounted) setState(() => _saved = saved);
    } catch (error) {
      if (mounted) {
        setState(() {
          _rights = oldRights;
          _conversion = oldConversion;
          _message = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _download() async {
    debugPrint('SYNCBEAT_DOWNLOAD requested');
    final video = _selected;
    if (_operation != null ||
        video == null ||
        _saved?.id != video.id ||
        !_authorization.valid) {
      debugPrint('SYNCBEAT_DOWNLOAD blocked by current selection/operation');
      return;
    }
    final token = DownloadCancellationToken();
    setState(() {
      _operation = token;
      _message = 'Download e conversione MP3…';
      _progress = null;
      _downloaded = null;
      _phase = 'Preparazione download';
    });
    _revealStatus();
    try {
      final authorization = _authorization;
      debugPrint('SYNCBEAT_DOWNLOAD saving confirmations');
      await _associations.saveAuthorization(
        widget.track.id,
        video.id,
        authorization,
      );
      final saved = await _associations.read(widget.track.id);
      if (mounted) setState(() => _saved = saved);
      token.throwIfCancelled();
      debugPrint('SYNCBEAT_DOWNLOAD starting downloader');
      final file =
          await (widget.downloader ??
                  YoutubeDownloader(
                    tools: widget.tools,
                    storage: widget.storage ?? PublicAudioStorage(),
                  ))
              .download(
                track: widget.track,
                video: video,
                authorization: authorization,
                cancellation: token,
                onProgress: (progress) {
                  if (mounted) setState(() => _progress = progress);
                },
                onPhase: (phase) {
                  debugPrint('SYNCBEAT_DOWNLOAD phase=$phase');
                  if (mounted) {
                    setState(() {
                      _phase = phase;
                      _progress = null;
                    });
                  }
                },
              );
      if (mounted) {
        setState(() {
          _downloaded = file;
          _message =
              'MP3 salvato in Download/SyncBeat: ${file.fileName}\n${file.path}';
        });
        _revealStatus();
      }
    } catch (error) {
      // Log only the error type; full details remain in the user's dialog.
      debugPrint('SYNCBEAT_DOWNLOAD failed type=${error.runtimeType}');
      if (mounted) setState(() => _message = '$error');
      _revealStatus();
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _openDownloaded(bool folder) async {
    try {
      await PublicAudioStorage.open(_downloaded!.path, folder: folder);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('YouTube · ${widget.track.title}'),
    content: SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.track.artistLine} · Spotify ${widget.track.durationMs ~/ 1000} s',
            ),
            const Text(
              'Fino a 10 risultati. Il punteggio suggerisce una corrispondenza: scegli e salva manualmente dopo l’ascolto.',
            ),
            if (_saved != null)
              ListTile(
                title: Text('Scelta salvata in precedenza: ${_saved!.title}'),
                subtitle: Text(_saved!.url.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_browser),
                  onPressed: () => _open(_saved!),
                ),
                onTap: _operation != null ? null : () => _choose(_saved),
              ),
            FilledButton.icon(
              onPressed: _operation == null ? _search : null,
              icon: const Icon(Icons.search),
              label: const Text('Cerca su YouTube'),
            ),
            if (Platform.isAndroid)
              TextButton(
                onPressed: _operation == null ? _updateAndroidEngine : null,
                child: const Text('Aggiorna motore YouTube'),
              ),
            if (_saved != null)
              const Text(
                'La scelta salvata non è il nuovo suggerimento. Esegui una nuova ricerca e salva esplicitamente se vuoi sostituirla.',
              ),
            SizedBox(key: _statusPanel, height: 0),
            if (_operation != null) ...[
              LinearProgressIndicator(value: _progress?.fraction),
              Text(
                _progress?.fraction == null
                    ? _phase
                    : '$_phase · ${(_progress!.fraction! * 100).toStringAsFixed(0)}%',
              ),
              TextButton(
                onPressed: () => _operation?.cancel(),
                child: const Text('Annulla operazione'),
              ),
            ],
            if (_message != null) SelectableText(_message!),
            if (_downloaded != null)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _openDownloaded(false),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Apri file'),
                  ),
                  TextButton.icon(
                    onPressed: () => _openDownloaded(true),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Apri cartella'),
                  ),
                ],
              ),
            if (_selected != null) ...[
              Text('Video scelto: ${_selected!.title}', key: _selectionPanel),
              FilledButton(
                onPressed: _operation == null ? _save : null,
                child: const Text('Salva associazione Spotify → YouTube'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Salva l’associazione e conferma i permessi per abilitare Scarica MP3. Destinazione: Download/SyncBeat.',
              ),
              const Text(
                'Download autorizzato: la presenza su YouTube o una licenza dichiarata non verificano da sole il permesso della piattaforma.',
              ),
              CheckboxListTile(
                value: _rights,
                onChanged: _operation != null
                    ? null
                    : (v) => _changeApproval(rights: v ?? false),
                title: const Text(
                  'Confermo i diritti e il permesso della piattaforma per scaricare questo video.',
                ),
              ),
              CheckboxListTile(
                value: _conversion,
                onChanged: _operation != null
                    ? null
                    : (v) => _changeApproval(conversion: v ?? false),
                title: const Text(
                  'L’autorizzazione include conversione MP3 e uso offline.',
                ),
              ),
            ],
            if (_results.any((r) => r.ambiguous))
              const Text(
                'Risultato ambiguo: i migliori candidati hanno punteggi molto simili. Confrontali nel browser.',
              ),
            RadioGroup<String>(
              groupValue: _selected?.id,
              onChanged: _operation != null
                  ? (_) {}
                  : (id) => _choose(
                      _results.firstWhere((r) => r.video.id == id).video,
                    ),
              child: Column(
                children: [
                  for (var index = 0; index < _results.length; index++)
                    _result(_results[index], index == 0),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (_selected != null)
        FilledButton.icon(
          onPressed:
              _operation == null &&
                  _saved?.id == _selected?.id &&
                  _authorization.valid
              ? _download
              : null,
          icon: const Icon(Icons.download),
          label: const Text('Scarica MP3'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Chiudi'),
      ),
    ],
  );

  Widget _result(RankedYoutubeVideo result, bool best) {
    final video = result.video;
    return Card(
      color: best ? Theme.of(context).colorScheme.primaryContainer : null,
      child: RadioListTile<String>(
        value: video.id,
        title: Text('${best ? 'Miglior candidato · ' : ''}${video.title}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (video.thumbnail != null)
              Image.network(
                video.thumbnail!,
                width: 160,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.video_library),
              ),
            Text(
              '${video.channel} · ${video.duration > 0 ? '${video.duration ~/ 60}:${(video.duration % 60).toString().padLeft(2, '0')}' : 'Durata sconosciuta'} · ${result.score.toStringAsFixed(1)}/100',
            ),
            if (video.channelInfo?.oac == OacStatus.confirmed)
              const Text('Artista ufficiale · OAC confermato'),
            if (video.channelInfo?.verification == ChannelVerification.verified)
              const Text('Canale verificato'),
            if (video.channelInfo?.verification ==
                ChannelVerification.unverified)
              const Text('Canale non verificato nei metadati'),
            if (video.channelInfo?.verification == ChannelVerification.unknown)
              const Text('Stato verifica canale sconosciuto'),
            if (video.channelInfo?.isTopic == true) const Text('Topic'),
            if (video.channelInfo?.isLabel == true)
              const Text('Etichetta / distributore'),
            if (video.channelInfo?.oac == OacStatus.unknown)
              const Text('Stato OAC sconosciuto'),
            if (video.channelUrl != null)
              TextButton(
                onPressed: () => _openUri(video.channelUrl!),
                child: const Text('Apri canale'),
              ),
            for (final reason in result.reasons) Text(reason),
            SelectableText(video.url.toString()),
            TextButton.icon(
              onPressed: () => _open(video),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Apri e ascolta nel browser'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUri(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const AudioSourceException('Impossibile aprire il browser.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }
}
