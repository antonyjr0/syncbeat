import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'features/audio_sources/audio_match_dialog.dart';
import 'features/audio_sources/local_audio_library.dart';
import 'features/audio_sources/youtube_match_dialog.dart';
import 'models/spotify_models.dart';
import 'services/metadata_cache.dart';
import 'services/spotify_api_service.dart';
import 'services/spotify_auth_service.dart';

class SyncBeatApp extends StatelessWidget {
  const SyncBeatApp({
    super.key,
    this.authService,
    this.apiService,
    this.metadataStore,
  });

  final SpotifyAuthService? authService;
  final SpotifyApiService? apiService;
  final MetadataStore? metadataStore;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF183A32);
    const leaf = Color(0xFF3B8065);
    const canvas = Color(0xFFF3F6F1);
    return MaterialApp(
      title: 'SyncBeat',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: leaf,
              brightness: Brightness.light,
            ).copyWith(
              primary: ink,
              secondary: const Color(0xFFD66C45),
              surface: Colors.white,
            ),
        scaffoldBackgroundColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: ink,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD9E2D9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD9E2D9)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: SyncBeatHomePage(
        authService: authService,
        apiService: apiService,
        metadataStore: metadataStore,
      ),
    );
  }
}

class SyncBeatHomePage extends StatefulWidget {
  const SyncBeatHomePage({
    super.key,
    this.authService,
    this.apiService,
    this.metadataStore,
  });

  final SpotifyAuthService? authService;
  final SpotifyApiService? apiService;
  final MetadataStore? metadataStore;

  @override
  State<SyncBeatHomePage> createState() => _SyncBeatHomePageState();
}

class _SyncBeatHomePageState extends State<SyncBeatHomePage> {
  late final SpotifyAuthService _auth;
  late final SpotifyApiService _spotify;
  late final MetadataStore _metadata;
  final _trackInput = TextEditingController();

  bool _restoring = true;
  bool _connected = false;
  String? _selectedPlaylistId;
  String? _busyAction;
  String? _errorMessage;
  List<SpotifyPlaylist> _playlists = [];
  List<SpotifyTrack> _tracks = [];
  List<TrackImportResult> _importResults = [];

  @override
  void initState() {
    super.initState();
    _auth =
        widget.authService ??
        SpotifyAuthService(secureTokenStore: SecureSpotifyTokenStore());
    _spotify = widget.apiService ?? SpotifyApiService(tokenService: _auth);
    _metadata = widget.metadataStore ?? MetadataCache();
    _restoreLocalState();
  }

  @override
  void dispose() {
    _trackInput.dispose();
    super.dispose();
  }

  Future<void> _restoreLocalState() async {
    try {
      final playlists = await _metadata.readPlaylists();
      final selectedId = await _metadata.readSelectedPlaylistId();
      final tracks = await _metadata.readTracks();
      final tokens = await _auth.storedTokens;
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _selectedPlaylistId = playlists.any((item) => item.id == selectedId)
            ? selectedId
            : null;
        _tracks = tracks;
        _connected = tokens != null;
        _restoring = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _errorMessage = 'Impossibile leggere i dati locali: $error';
      });
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busyAction = 'connect';
      _errorMessage = null;
    });
    try {
      await _auth.signIn();
      if (!mounted) return;
      setState(() => _connected = true);
      await _loadPlaylists();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _disconnect() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _playlists = [];
      _selectedPlaylistId = null;
      _errorMessage = null;
    });
    await _metadata.writeSelectedPlaylistId(null);
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _busyAction = 'playlists';
      _errorMessage = null;
    });
    try {
      final playlists = await _spotify.getCurrentUserPlaylists();
      final previousSelection = _selectedPlaylistId;
      final selectedId = playlists.any((item) => item.id == previousSelection)
          ? previousSelection
          : null;
      await _metadata.writePlaylists(playlists);
      await _metadata.writeSelectedPlaylistId(selectedId);
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _selectedPlaylistId = selectedId;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _selectPlaylist(String? playlistId) async {
    setState(() => _selectedPlaylistId = playlistId);
    await _metadata.writeSelectedPlaylistId(playlistId);
  }

  Future<void> _loadPlaylistTracks() async {
    final playlistId = _selectedPlaylistId;
    if (playlistId == null) return;
    setState(() {
      _busyAction = 'tracks';
      _errorMessage = null;
    });
    try {
      final tracks = await _spotify.getPlaylistTracks(playlistId);
      await _metadata.writeTracks(tracks);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _importResults = [];
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _importTestTracks() => _importTrackIds(AppConfig.testTrackIds);

  Future<void> _importManualTrack() async {
    final trackId = _parseTrackId(_trackInput.text.trim());
    if (trackId == null) {
      _showError(
        const FormatException(
          'Inserisci un ID o link Spotify a un brano valido.',
        ),
      );
      return;
    }
    await _importTrackIds([trackId]);
    _trackInput.clear();
  }

  String? _parseTrackId(String input) {
    if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(input)) return input;
    if (input.startsWith('spotify:track:')) {
      final id = input.substring('spotify:track:'.length);
      return RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id) ? id : null;
    }
    final uri = Uri.tryParse(input);
    if (uri?.host == 'open.spotify.com') {
      final segments = uri!.pathSegments;
      final index = segments.indexOf('track');
      if (index >= 0 && index + 1 < segments.length) {
        final id = segments[index + 1];
        return RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id) ? id : null;
      }
    }
    return null;
  }

  Future<void> _importTrackIds(Iterable<String> trackIds) async {
    setState(() {
      _busyAction = 'import';
      _errorMessage = null;
    });
    try {
      final results = await _spotify.importTrackIds(trackIds);
      final importedTracks = results
          .map((result) => result.track)
          .whereType<SpotifyTrack>()
          .toList(growable: false);
      final mergedTracks = [..._tracks];
      for (final track in importedTracks) {
        mergedTracks.removeWhere((existing) => existing.id == track.id);
        mergedTracks.add(track);
      }
      await _metadata.writeTracks(mergedTracks);
      if (!mounted) return;
      setState(() {
        _tracks = mergedTracks;
        _importResults = results;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _errorMessage = error.toString());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
                24,
                MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
                48,
              ),
              children: [
                _buildHeader(colorScheme),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LocalAudioLibrary(),
                      ),
                    ),
                    icon: const Icon(Icons.library_music),
                    label: const Text('MP3 locali · ascolta'),
                  ),
                ),
                const SizedBox(height: 28),
                _buildConnectionPanel(colorScheme),
                const SizedBox(height: 28),
                _buildSetupStatus(colorScheme),
                const SizedBox(height: 30),
                _buildPlaylistSection(colorScheme),
                const SizedBox(height: 30),
                _buildTrackSection(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
          650;
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.headphones_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SyncBeat',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'AMAZFIT ACTIVE 3 PREMIUM  /  LIBRERIA OFFLINE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF68796F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final status = _StatusPill(
        label: _connected ? 'SPOTIFY COLLEGATO' : 'CONFIGURAZIONE',
        color: _connected ? const Color(0xFF2C785B) : const Color(0xFFBB633E),
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [identity, const SizedBox(height: 12), status],
        );
      }
      return Row(
        children: [
          Expanded(child: identity),
          const SizedBox(width: 20),
          status,
        ],
      );
    },
  );

  Widget _buildConnectionPanel(ColorScheme colors) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
          650;
      final accountIcon = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFE9F2EC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.music_note_rounded, color: colors.primary),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _connected ? 'Account Spotify' : 'Collega Spotify',
            key: const ValueKey('spotify-account-title'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _connected
                ? 'Playlist e metadati disponibili per l\u2019importazione.'
                : 'Accesso sicuro con OAuth 2.0 e PKCE.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF68796F)),
          ),
        ],
      );
      final info =
          compact &&
              (constraints.maxWidth - 32) /
                      MediaQuery.textScalerOf(context).scale(1) <
                  240
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [accountIcon, const SizedBox(height: 12), details],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                accountIcon,
                const SizedBox(width: 14),
                Expanded(child: details),
              ],
            );
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_connected) ...[
            OutlinedButton.icon(
              onPressed: _busyAction == null ? _loadPlaylists : null,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Aggiorna'),
            ),
            IconButton(
              tooltip: 'Disconnetti Spotify',
              onPressed: _busyAction == null ? _disconnect : null,
              icon: const Icon(Icons.logout_rounded),
            ),
          ] else
            FilledButton.icon(
              onPressed: _busyAction == null && !_restoring ? _connect : null,
              icon: _busyAction == 'connect'
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(
                _busyAction == 'connect' ? 'In attesa...' : 'Collega account',
              ),
            ),
        ],
      );
      return Container(
        key: const ValueKey('spotify-connection-panel'),
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 16 : 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDCE5DC)),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [info, const SizedBox(height: 16), actions],
              )
            : Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 24),
                  actions,
                ],
              ),
      );
    },
  );

  Widget _buildSetupStatus(ColorScheme colors) {
    final statuses = [
      _SetupStatus(
        'Spotify',
        _connected ? 'Connesso' : 'In attesa',
        _connected,
      ),
      _SetupStatus(
        'Provider Jamendo',
        AppConfig.jamendoClientId.isEmpty
            ? 'Client ID richiesto'
            : 'Ricerca pronta',
        AppConfig.jamendoClientId.isNotEmpty,
      ),
      const _SetupStatus(
        'YouTube · provider principale',
        'Ricerca yt-dlp su Windows e Android',
        true,
      ),
      const _SetupStatus('Download offline', 'Autorizzazione richiesta', false),
      const _SetupStatus('Cartella staging', 'Directory privata app', false),
      const _SetupStatus('Handoff Zepp', 'Importazione manuale', false),
      const _SetupStatus('Database Appwrite', 'Da collegare', false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stato configurazione',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEAF0E9),
            borderRadius: BorderRadius.circular(10),
          ),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns = ((constraints.maxWidth + 24) / (220 * scale + 24))
                  .floor()
                  .clamp(1, 5);
              final tileWidth =
                  (constraints.maxWidth - 24 * (columns - 1)) / columns;
              return Wrap(
                spacing: 24,
                runSpacing: 4,
                children: statuses
                    .map(
                      (status) => SizedBox(
                        width: tileWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                status.complete
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 17,
                                color: status.complete
                                    ? const Color(0xFF33765A)
                                    : const Color(0xFF9A6E51),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      status.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      status.value,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: const Color(0xFF68796F),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE9B49B)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFF9C4528),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFF74381F)),
                  ),
                ),
                IconButton(
                  tooltip: 'Chiudi avviso',
                  onPressed: () => setState(() => _errorMessage = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaylistSection(ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: _SectionHeading(
              eyebrow: 'LIBRERIA',
              title: 'Le tue playlist',
              colors: colors,
            ),
          ),
          if (_busyAction == 'playlists' || _busyAction == 'tracks')
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      const SizedBox(height: 14),
      if (!_connected)
        const _EmptySection(
          icon: Icons.lock_outline_rounded,
          label:
              'Collega Spotify per caricare le playlist accessibili al tuo account.',
        )
      else if (_playlists.isEmpty)
        const _EmptySection(
          icon: Icons.queue_music_rounded,
          label:
              'Nessuna playlist accessibile. Puoi importare singoli ID più sotto.',
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final dropdown = DropdownButtonFormField<String>(
              initialValue: _selectedPlaylistId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Playlist Spotify',
                prefixIcon: Icon(Icons.queue_music_rounded),
              ),
              items: _playlists
                  .map(
                    (playlist) => DropdownMenuItem(
                      value: playlist.id,
                      child: Text(
                        '${playlist.name}  ·  ${playlist.trackCount} brani',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busyAction == null ? _selectPlaylist : null,
            );
            final loadButton = FilledButton.icon(
              onPressed: _busyAction == null && _selectedPlaylistId != null
                  ? _loadPlaylistTracks
                  : null,
              icon: const Icon(Icons.download_for_offline_outlined, size: 18),
              label: const Text('Carica brani'),
            );
            if (constraints.maxWidth /
                    MediaQuery.textScalerOf(context).scale(1) <
                560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [dropdown, const SizedBox(height: 10), loadButton],
              );
            }
            return Row(
              children: [
                Expanded(child: dropdown),
                const SizedBox(width: 10),
                loadButton,
              ],
            );
          },
        ),
    ],
  );

  Widget _buildTrackSection(ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _SectionHeading(
              eyebrow: 'METADATI SPOTIFY',
              title: 'Brani importati',
              colors: colors,
            ),
          ),
          if (_tracks.isNotEmpty)
            Text(
              '${_tracks.length} brani',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: const Color(0xFF68796F)),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: _busyAction == null && _connected
                ? _importTestTracks
                : null,
            icon: _busyAction == 'import'
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add_rounded, size: 18),
            label: Text(
              _busyAction == 'import'
                  ? 'Importazione...'
                  : 'Importa i 16 ID test',
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busyAction == null
                ? () => _importTrackIds([AppConfig.testTrackIds.first])
                : null,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('Prova un ID'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final input = TextField(
            controller: _trackInput,
            enabled: _connected && _busyAction == null,
            onSubmitted: (_) => _importManualTrack(),
            decoration: const InputDecoration(
              labelText: 'ID o link Spotify del brano',
              hintText: 'spotify:track:… oppure open.spotify.com/track/…',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          );
          final submit = FilledButton.tonalIcon(
            onPressed: _connected && _busyAction == null
                ? _importManualTrack
                : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Importa'),
          );
          if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [input, const SizedBox(height: 8), submit],
            );
          }
          return Row(
            children: [
              Expanded(child: input),
              const SizedBox(width: 10),
              submit,
            ],
          );
        },
      ),
      if (_importResults.any((result) => result.error != null)) ...[
        const SizedBox(height: 14),
        ..._importResults
            .where((result) => result.error != null)
            .map(
              (result) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${result.trackId}: ${result.error}',
                  style: const TextStyle(color: Color(0xFF9C4528)),
                ),
              ),
            ),
      ],
      const SizedBox(height: 18),
      if (_tracks.isEmpty)
        const _EmptySection(
          icon: Icons.album_outlined,
          label: 'I metadati importati appariranno qui.',
        )
      else
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDCE5DC)),
          ),
          child: Column(
            children: [
              for (var index = 0; index < _tracks.length; index++) ...[
                _TrackRow(
                  track: _tracks[index],
                  onYoutube: () => showDialog<void>(
                    context: context,
                    builder: (_) => YoutubeMatchDialog(track: _tracks[index]),
                  ),
                  onFindAudio: () => showDialog<void>(
                    context: context,
                    builder: (_) => AudioMatchDialog(track: _tracks[index]),
                  ),
                ),
                if (index != _tracks.length - 1)
                  const Divider(height: 1, indent: 64),
              ],
            ],
          ),
        ),
    ],
  );
}

class _SetupStatus {
  const _SetupStatus(this.label, this.value, this.complete);

  final String label;
  final String value;
  final bool complete;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.colors,
  });

  final String eyebrow;
  final String title;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFFB6603C),
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.72),
      border: Border.all(color: const Color(0xFFDCE5DC)),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF738579)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF68796F))),
        ),
      ],
    ),
  );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.onFindAudio,
    required this.onYoutube,
  });

  final SpotifyTrack track;
  final VoidCallback onFindAudio;
  final VoidCallback onYoutube;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width /
            MediaQuery.textScalerOf(context).scale(1) <
        600;
    final imageUrl = track.imageUrl;
    final minutes = track.durationMs ~/ 60000;
    final seconds = (track.durationMs % 60000) ~/ 1000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox.square(
              dimension: 42,
              child: imageUrl == null
                  ? const ColoredBox(
                      color: Color(0xFFEAF0E9),
                      child: Icon(
                        Icons.album_outlined,
                        color: Color(0xFF3B8065),
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFEAF0E9),
                        child: Icon(
                          Icons.album_outlined,
                          color: Color(0xFF3B8065),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF183A32),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${track.artistLine}${track.album.isEmpty ? '' : '  ·  ${track.album}'}',
                  maxLines: compact ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF68796F),
                    fontSize: 12,
                  ),
                ),
                if (compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Color(0xFF68796F)),
                  ),
                ],
                TextButton.icon(
                  onPressed: onYoutube,
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('YouTube / MP3'),
                ),
              ],
            ),
          ),
          if (!compact) const SizedBox(width: 12),
          if (!compact)
            Text(
              '$minutes:${seconds.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Color(0xFF68796F),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          IconButton(
            tooltip: 'Cerca una fonte audio autorizzata',
            onPressed: onFindAudio,
            icon: const Icon(Icons.library_music_outlined),
          ),
        ],
      ),
    );
  }
}
