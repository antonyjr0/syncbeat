import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/syncbeat_theme.dart';

import '../../config/app_config.dart';
import '../../models/spotify_models.dart';
import 'audio_source.dart';
import 'jamendo_downloader.dart';
import 'jamendo_provider.dart';
import 'local_mp3_provider.dart';
import 'staging_storage.dart';
import 'track_matcher.dart';
import 'youtube_match_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class AudioMatchDialog extends StatefulWidget {
  const AudioMatchDialog({
    required this.track,
    this.jamendoProvider,
    this.localProvider,
    this.downloadManager,
    this.matcher,
    super.key,
  });

  final SpotifyTrack track;
  final JamendoProvider? jamendoProvider;
  final LocalMp3Provider? localProvider;
  final AudioDownloadManager? downloadManager;
  final TrackMatcher? matcher;

  @override
  State<AudioMatchDialog> createState() => _AudioMatchDialogState();
}

class _AudioMatchDialogState extends State<AudioMatchDialog> {
  late final JamendoProvider _jamendo;
  late final LocalMp3Provider _local;
  late final AudioDownloadManager _downloads;
  late final TrackMatcher _matcher;

  AudioMatchResult? _result;
  AudioCandidate? _selectedCandidate;
  StagedAudioFile? _stagedFile;
  DownloadCancellationToken? _cancellationToken;
  DownloadProgress? _progress;
  bool _searching = false;
  bool _downloading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final storage = AppDirectoryStagingStorage();
    _jamendo = widget.jamendoProvider ?? JamendoProvider();
    _local = widget.localProvider ?? LocalMp3Provider(stagingStorage: storage);
    _downloads =
        widget.downloadManager ??
        AudioDownloadManager([
          JamendoAudioDownloader(
            stagingStorage: storage,
            offlineUseAuthorized: AppConfig.jamendoOfflineUseAuthorized,
          ),
          _local,
        ]);
    _matcher = widget.matcher ?? TrackMatcher();
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    super.dispose();
  }

  Future<void> _searchJamendo() async {
    setState(() {
      _searching = true;
      _errorMessage = null;
      _result = null;
      _selectedCandidate = null;
      _stagedFile = null;
    });
    try {
      final candidates = await _jamendo.search(widget.track);
      final result = _matcher.match(widget.track, candidates);
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result.status == TrackMatchStatus.confident) {
          _selectedCandidate = result.candidates.first.candidate;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<bool> _confirmLocalRights() async {
    var confirmed = false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('Diritti sul file'),
              content: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) => setDialogState(() {
                  confirmed = value ?? false;
                }),
                title: Text(
                  'Confermo di avere il diritto di usare questo MP3 offline.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Annulla'),
                ),
                FilledButton(
                  onPressed: confirmed
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: Text('Continua'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _pickLocalMp3() async {
    final confirmed = await _confirmLocalRights();
    if (!confirmed || !mounted) return;
    setState(() {
      _searching = true;
      _errorMessage = null;
      _stagedFile = null;
    });
    try {
      final candidates = await _local.pickFiles(userConfirmedRights: true);
      if (!mounted) return;
      if (candidates.isEmpty) {
        setState(
          () => _errorMessage = 'Nessun file MP3 leggibile selezionato.',
        );
        return;
      }
      final candidate = await showDialog<AudioCandidate>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Associa un MP3 al brano'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: candidates
                  .map(
                    (item) => ListTile(
                      leading: Icon(Icons.audio_file_rounded),
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.artist.isEmpty ? 'Artista non disponibile' : item.artist} · ${_formatDuration(item.durationSeconds)}',
                      ),
                      onTap: () => Navigator.pop(context, item),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annulla'),
            ),
          ],
        ),
      );
      if (candidate == null || !mounted) return;
      setState(() {
        _selectedCandidate = candidate.forSpotifyTrack(widget.track);
        _result = AudioMatchResult(
          track: widget.track,
          candidates: [
            ScoredAudioCandidate(candidate: _selectedCandidate!, confidence: 0),
          ],
          status: TrackMatchStatus.manualSelectionRequired,
        );
      });
    } catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _downloadSelected() async {
    final candidate = _selectedCandidate;
    if (candidate == null || !_downloads.canDownload(candidate)) return;
    final cancellationToken = DownloadCancellationToken();
    setState(() {
      _downloading = true;
      _cancellationToken = cancellationToken;
      _errorMessage = null;
      _progress = DownloadProgress(receivedBytes: 0);
    });
    try {
      final stagedFile = await _downloads.download(
        candidate,
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _stagedFile = stagedFile);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _cancellationToken = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    content: SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 64, 680),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.track.artistLine,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _searching || _downloading
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              YoutubeMatchDialog(track: widget.track),
                        ),
                  icon: Icon(Icons.video_library),
                  label: Text('YouTube · ricerca principale'),
                ),
                FilledButton.icon(
                  onPressed: _searching || _downloading ? null : _searchJamendo,
                  icon: _searching
                      ? SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.search_rounded, size: 18),
                  label: Text('Cerca su Jamendo'),
                ),
                OutlinedButton.icon(
                  onPressed: _searching || _downloading ? null : _pickLocalMp3,
                  icon: Icon(Icons.folder_open_rounded, size: 18),
                  label: Text('Scegli MP3 locale'),
                ),
              ],
            ),
            if (!_jamendo.isConfigured) ...[
              SizedBox(height: 10),
              Text(
                'Jamendo richiede JAMENDO_CLIENT_ID configurato con --dart-define.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result != null) ...[
              SizedBox(height: 16),
              _buildResultSummary(context),
              SizedBox(height: 8),
              RadioGroup<AudioCandidate>(
                groupValue: _selectedCandidate,
                onChanged: (candidate) =>
                    setState(() => _selectedCandidate = candidate),
                child: Column(
                  children: [
                    for (final item in _result!.candidates)
                      _buildCandidate(context, item),
                  ],
                ),
              ),
            ],
            if (_downloading) ...[
              SizedBox(height: 16),
              LinearProgressIndicator(value: _progress?.fraction),
              SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progress?.totalBytes == null
                          ? '${_formatBytes(_progress?.receivedBytes ?? 0)} ricevuti'
                          : '${_formatBytes(_progress!.receivedBytes)} / ${_formatBytes(_progress!.totalBytes!)}',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _cancellationToken?.cancel(),
                    icon: Icon(Icons.close_rounded, size: 17),
                    label: Text('Annulla'),
                  ),
                ],
              ),
            ],
            if (_stagedFile != null) ...[
              SizedBox(height: 12),
              Text(
                'Salvato nello staging: ${_stagedFile!.fileName} · ${_formatBytes(_stagedFile!.sizeBytes)}',
                style: TextStyle(
                  color: SyncBeatStatusColors.of(context).success,
                ),
              ),
            ],
            if (_result?.status == TrackMatchStatus.noMatch) ...[
              SizedBox(height: 14),
              Text(
                'Nessuna corrispondenza verificata. Non è disponibile alcun download.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (_selectedCandidate != null)
        FilledButton.icon(
          onPressed:
              !_downloading && _downloads.canDownload(_selectedCandidate!)
              ? _downloadSelected
              : null,
          icon: Icon(Icons.download_rounded, size: 18),
          label: Text(
            _selectedCandidate!.isLocalFile
                ? 'Copia nello staging'
                : 'Scarica MP3',
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Chiudi'),
      ),
    ],
  );

  Widget _buildResultSummary(BuildContext context) {
    final result = _result!;
    final summary = switch (result.status) {
      TrackMatchStatus.confident => 'Corrispondenza affidabile',
      TrackMatchStatus.manualSelectionRequired => 'Selezione manuale richiesta',
      TrackMatchStatus.noMatch => 'Nessuna corrispondenza',
    };
    return Text(
      '$summary · ${result.candidates.length} risultati',
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildCandidate(BuildContext context, ScoredAudioCandidate scored) {
    final candidate = scored.candidate;
    final selected =
        _selectedCandidate?.id == candidate.id &&
        _selectedCandidate?.providerId == candidate.providerId;
    final confidenceLabel =
        candidate.isLocalFile &&
            _result?.status == TrackMatchStatus.manualSelectionRequired
        ? 'Scelta manuale'
        : '${(scored.confidence * 100).round()}%';
    final licenseLabel = candidate.license.restrictionReason == null
        ? candidate.license.name
        : '${candidate.license.name} · ${candidate.license.restrictionReason}';
    return Container(
      margin: EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RadioListTile<AudioCandidate>(
        value: candidate,
        title: Text(
          candidate.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${candidate.artist} · ${_formatDuration(candidate.durationSeconds)}',
              ),
              Text('Fonte: ${candidate.providerId} · $confidenceLabel'),
              Text('Licenza: $licenseLabel'),
              if (candidate.license.attribution != null)
                Text(candidate.license.attribution!),
              if (candidate.sourceUrl != null)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    candidate.sourceUrl!,
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text('Apri pagina della fonte'),
                ),
              if (candidate.quality != null)
                Text('Qualità: ${candidate.quality}'),
              if (candidate.estimatedSizeBytes != null)
                Text(
                  '${candidate.isLocalFile ? 'Dimensione file' : 'Spazio stimato'}: ${_formatBytes(candidate.estimatedSizeBytes!)}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
