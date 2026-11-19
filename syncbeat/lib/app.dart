import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'theme/syncbeat_theme.dart';
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
    return MaterialApp(
      title: 'SyncBeat',
      theme: SyncBeatTheme.build(Brightness.light),
      darkTheme: SyncBeatTheme.build(Brightness.dark),
      themeMode: ThemeMode.system,
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
        FormatException('Inserisci un ID o link Spotify a un brano valido.'),
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
            constraints: BoxConstraints(maxWidth: 1120),
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
                        builder: (_) => LocalAudioLibrary(),
                      ),
                    ),
                    icon: Icon(Icons.library_music),
                    label: Text('MP3 locali · ascolta'),
                  ),
                ),
                SizedBox(height: 28),
                _buildConnectionPanel(colorScheme),
                SizedBox(height: 28),
                _buildSetupStatus(colorScheme),
                SizedBox(height: 30),
                _buildPlaylistSection(colorScheme),
                SizedBox(height: 30),
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
          Image.asset(
            'assets/branding/app_icon.png',
            width: 52,
            height: 52,
            semanticLabel: 'Logo SyncBeat',
          ),
          SizedBox(width: 14),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        color: _connected
            ? SyncBeatStatusColors.of(context).success
            : SyncBeatStatusColors.of(context).warning,
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [identity, SizedBox(height: 12), status],
        );
      }
      return Row(
        children: [
          Expanded(child: identity),
          SizedBox(width: 20),
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
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.music_note_rounded, color: colors.primary),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _connected ? 'Account Spotify' : 'Collega Spotify',
            key: ValueKey('spotify-account-title'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          SizedBox(height: 3),
          Text(
            _connected
                ? 'Playlist e metadati disponibili per l\u2019importazione.'
                : 'Accesso sicuro con OAuth 2.0 e PKCE.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
              children: [accountIcon, SizedBox(height: 12), details],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                accountIcon,
                SizedBox(width: 14),
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
              icon: Icon(Icons.refresh_rounded, size: 18),
              label: Text('Aggiorna'),
            ),
            IconButton(
              tooltip: 'Disconnetti Spotify',
              onPressed: _busyAction == null ? _disconnect : null,
              icon: Icon(Icons.logout_rounded),
            ),
          ] else
            FilledButton.icon(
              onPressed: _busyAction == null && !_restoring ? _connect : null,
              icon: _busyAction == 'connect'
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.link_rounded, size: 18),
              label: Text(
                _busyAction == 'connect' ? 'In attesa...' : 'Collega account',
              ),
            ),
        ],
      );
      return Container(
        key: ValueKey('spotify-connection-panel'),
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 16 : 22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [info, SizedBox(height: 16), actions],
              )
            : Row(
                children: [
                  Expanded(child: info),
                  SizedBox(width: 24),
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
      _SetupStatus(
        'YouTube · provider principale',
        'Ricerca yt-dlp su Windows e Android',
        true,
      ),
      _SetupStatus('Download offline', 'Autorizzazione richiesta', false),
      _SetupStatus('Cartella staging', 'Directory privata app', false),
      _SetupStatus(
        'Handoff Zepp',
        'Manuale, o invio diretto da MP3 locali (sperimentale, Android)',
        false,
      ),
      _SetupStatus('Database Appwrite', 'Da collegare', false),
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
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                status.complete
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 17,
                                color: status.complete
                                    ? SyncBeatStatusColors.of(context).success
                                    : SyncBeatStatusColors.of(context).warning,
                              ),
                              SizedBox(width: 8),
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
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
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
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.error),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Chiudi avviso',
                  onPressed: () => setState(() => _errorMessage = null),
                  icon: Icon(Icons.close_rounded, size: 18),
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
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      SizedBox(height: 14),
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
              decoration: InputDecoration(
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
              icon: Icon(Icons.download_for_offline_outlined, size: 18),
              label: Text('Carica brani'),
            );
            if (constraints.maxWidth /
                    MediaQuery.textScalerOf(context).scale(1) <
                560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [dropdown, SizedBox(height: 10), loadButton],
              );
            }
            return Row(
              children: [
                Expanded(child: dropdown),
                SizedBox(width: 10),
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
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: _busyAction == null && _connected
                ? _importTestTracks
                : null,
            icon: _busyAction == 'import'
                ? SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.playlist_add_rounded, size: 18),
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
            icon: Icon(Icons.science_outlined, size: 18),
            label: Text('Prova un ID'),
          ),
        ],
      ),
      SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final input = TextField(
            controller: _trackInput,
            enabled: _connected && _busyAction == null,
            onSubmitted: (_) => _importManualTrack(),
            decoration: InputDecoration(
              labelText: 'ID o link Spotify del brano',
              hintText: 'spotify:track:… oppure open.spotify.com/track/…',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          );
          final submit = FilledButton.tonalIcon(
            onPressed: _connected && _busyAction == null
                ? _importManualTrack
                : null,
            icon: Icon(Icons.add_rounded, size: 18),
            label: Text('Importa'),
          );
          if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [input, SizedBox(height: 8), submit],
            );
          }
          return Row(
            children: [
              Expanded(child: input),
              SizedBox(width: 10),
              submit,
            ],
          );
        },
      ),
      if (_importResults.any((result) => result.error != null)) ...[
        SizedBox(height: 14),
        ..._importResults
            .where((result) => result.error != null)
            .map(
              (result) => Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '${result.trackId}: ${result.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
      ],
      SizedBox(height: 18),
      if (_tracks.isEmpty)
        const _EmptySection(
          icon: Icons.album_outlined,
          label: 'I metadati importati appariranno qui.',
        )
      else
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
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
                if (index != _tracks.length - 1) Divider(height: 1, indent: 64),
              ],
            ],
          ),
        ),
    ],
  );
}

class _SetupStatus {
  _SetupStatus(this.label, this.value, this.complete);

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
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(height: 3),
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
    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox.square(
              dimension: 42,
              child: imageUrl == null
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Icon(
                        Icons.album_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: Icon(
                          Icons.album_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '${track.artistLine}${track.album.isEmpty ? '' : '  ·  ${track.album}'}',
                  maxLines: compact ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                if (compact) ...[
                  SizedBox(height: 4),
                  Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                TextButton.icon(
                  onPressed: onYoutube,
                  icon: Icon(Icons.video_library_outlined),
                  label: Text('YouTube / MP3'),
                ),
              ],
            ),
          ),
          if (!compact) SizedBox(width: 12),
          if (!compact)
            Text(
              '$minutes:${seconds.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          IconButton(
            tooltip: 'Cerca una fonte audio autorizzata',
            onPressed: onFindAudio,
            icon: Icon(Icons.library_music_outlined),
          ),
        ],
      ),
    );
  }
}
