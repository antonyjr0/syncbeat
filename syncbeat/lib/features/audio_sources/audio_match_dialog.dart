import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    _matcher = widget.matcher ?? const TrackMatcher();
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
              title: const Text('Diritti sul file'),
              content: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) => setDialogState(() {
                  confirmed = value ?? false;
                }),
                title: const Text(
                  'Confermo di avere il diritto di usare questo MP3 offline.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: confirmed
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Continua'),
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
          title: const Text('Associa un MP3 al brano'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: candidates
                  .map(
                    (item) => ListTile(
                      leading: const Icon(Icons.audio_file_rounded),
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
              child: const Text('Annulla'),
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
      _progress = const DownloadProgress(receivedBytes: 0);
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
            const SizedBox(height: 18),
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
                  icon: const Icon(Icons.video_library),
                  label: const Text('YouTube · ricerca principale'),
                ),
                FilledButton.icon(
                  onPressed: _searching || _downloading ? null : _searchJamendo,
                  icon: _searching
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Cerca su Jamendo'),
                ),
                OutlinedButton.icon(
                  onPressed: _searching || _downloading ? null : _pickLocalMp3,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Scegli MP3 locale'),
                ),
              ],
            ),
            if (!_jamendo.isConfigured) ...[
              const SizedBox(height: 10),
              const Text(
                'Jamendo richiede JAMENDO_CLIENT_ID configurato con --dart-define.',
                style: TextStyle(color: Color(0xFF68796F)),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFF9C4528)),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _buildResultSummary(context),
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress?.fraction),
              const SizedBox(height: 6),
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
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('Annulla'),
                  ),
                ],
              ),
            ],
            if (_stagedFile != null) ...[
              const SizedBox(height: 12),
              Text(
                'Salvato nello staging: ${_stagedFile!.fileName} · ${_formatBytes(_stagedFile!.sizeBytes)}',
                style: const TextStyle(color: Color(0xFF28664D)),
              ),
            ],
            if (_result?.status == TrackMatchStatus.noMatch) ...[
              const SizedBox(height: 14),
              const Text(
                'Nessuna corrispondenza verificata. Non è disponibile alcun download.',
                style: TextStyle(color: Color(0xFF68796F)),
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
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(
            _selectedCandidate!.isLocalFile
                ? 'Copia nello staging'
                : 'Scarica MP3',
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Chiudi'),
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
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? const Color(0xFF3B8065) : const Color(0xFFDCE5DC),
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
          padding: const EdgeInsets.only(top: 4),
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
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('Apri pagina della fonte'),
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
