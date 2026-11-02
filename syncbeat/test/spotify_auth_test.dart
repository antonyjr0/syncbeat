import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/services/spotify_auth_service.dart';

void main() {
  group('Spotify PKCE', () {
    test('creates an RFC 7636 length verifier and URL-safe challenge', () {
      final verifier = SpotifyAuthService.createCodeVerifier();
      final challenge = SpotifyAuthService.createCodeChallenge(verifier);

      expect(verifier, hasLength(64));
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9._~-]+$')));
      expect(challenge, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(challenge, isNot(contains('=')));
    });

    test('creates distinct state values', () {
      expect(
        SpotifyAuthService.createState(),
        isNot(SpotifyAuthService.createState()),
      );
    });
  });
}
