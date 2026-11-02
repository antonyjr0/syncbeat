class AppConfig {
  static const spotifyClientId = String.fromEnvironment(
    'SPOTIFY_CLIENT_ID',
    defaultValue: '1abb1e10cf8041c2957b9f748a26b8ad',
  );

  static const jamendoClientId = String.fromEnvironment('JAMENDO_CLIENT_ID');
  static const jamendoOfflineUseAuthorized = bool.fromEnvironment(
    'JAMENDO_OFFLINE_USE_AUTHORIZED',
    defaultValue: false,
  );

  static const windowsRedirectUri = 'http://127.0.0.1:8888/callback';
  static const androidRedirectUri = 'amazfitmusicsync://callback';
  static const testPlaylistId = '0j8M0X55dh5EC4fqlzy6uN';

  static const testTrackIds = <String>[
    '2K7bv4Q0FNNKPt4PPPCjOi',
    '0qYQaWV0956J7eouZaVmHn',
    '066ucxOm9btG4ApNim7Ohh',
    '7EOKcZX9TRkIs0nwWbCCbD',
    '1tISuPhzoKVIK3K9EDEC3E',
    '1BsPVfsb795RRceGK7rLSz',
    '3i4rci1J95OdMxer9kxjqW',
    '42BfRnednwP0IYXSDIPqfC',
    '1uwRaRWJiMiDD945IPdFbV',
    '3PYYiqmhooCNCGiiPTM5zS',
    '18NBoQ9SyURVcsPW6sP8tv',
    '5jT6gl92pmDlKy9689oZSX',
    '7L8cIUKXToCr6PV9hFoX3Q',
    '5E6zgNwpKQt25hBFowUIc0',
    '5dn2M3M51iMllhTt49eqhX',
    '0GuO6UjrzW2F0d2z0aOjmV',
  ];

  static const spotifyScopes = <String>[
    'playlist-read-private',
    'playlist-read-collaborative',
  ];
}
