import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'staging_storage.dart';
import 'public_audio_storage.dart';

class LocalAudioLibrary extends StatefulWidget {
  const LocalAudioLibrary({
    super.key,
    this.storage,
    this.legacyDirectory,
    this.android,
  });
  final PublicAudioStorage? storage;
  final Directory? legacyDirectory;
  final bool? android;
  @override
  State<LocalAudioLibrary> createState() => _LocalAudioLibraryState();
}

class _LocalAudioLibraryState extends State<LocalAudioLibrary> {
  bool get _android => widget.android ?? Platform.isAndroid;
  static const _channel = MethodChannel('syncbeat/youtube');
  List<PublishedAudio> _files = [];
  String? _error, _playing;
  int _position = 0, _duration = 0;
  Timer? _timer;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir =
          widget.legacyDirectory ??
          await AppDirectoryStagingStorage().directory;
      final legacy = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.mp3'))
          .cast<File>()
          .toList();
      final files = await (widget.storage ?? PublicAudioStorage()).list();
      // Keep old private downloads readable; new publications are indexed once.
      files.addAll(
        legacy.map((file) => PublishedAudio(file.path, p.basename(file.path))),
      );
      files.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) {
        setState(() {
          _files = files;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(PublishedAudio file) async {
    try {
      if (_android) {
        await _channel.invokeMethod<void>('play', {'path': file.path});
        if (!mounted) return;
        setState(() {
          _playing = file.path;
          _error = null;
        });
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      } else if (!await launchUrl(Uri.file(file.path))) {
        throw const FileSystemException('Impossibile aprire il lettore audio');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _poll() async {
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>(
        'playbackState',
      );
      if (mounted) {
        setState(() {
          _position = state?['positionMs'] as int? ?? 0;
          _duration = state?['durationMs'] as int? ?? 0;
          if (state?['error'] != null) _error = state!['error'] as String;
          if (state?['playing'] != true) _playing = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    try {
      await _channel.invokeMethod<void>('stop');
      if (mounted) setState(() => _playing = null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _licenses() async {
    try {
      final text = await _channel.invokeMethod<String>('licenses');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Licenze del motore Android'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: SelectableText(text ?? 'Licenze non disponibili'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_android) {
      unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MP3 locali'),
      actions: [
        if (_android)
          IconButton(
            tooltip: 'Licenze',
            onPressed: _licenses,
            icon: const Icon(Icons.info_outline),
          ),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              if (_files.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nessun MP3 salvato. Scarica un contenuto autorizzato in Download/SyncBeat.',
                  ),
                ),
              if (_playing != null)
                ListTile(
                  title: Text('Riproduzione: ${p.basename(_playing!)}'),
                  subtitle: Text(
                    '${_position ~/ 1000} / ${_duration ~/ 1000} s',
                  ),
                  trailing: IconButton(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.audio_file),
                    title: Text(_files[i].name),
                    subtitle: Text(_files[i].path),
                    trailing: IconButton(
                      tooltip: 'Riproduci',
                      onPressed: () => _play(_files[i]),
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
