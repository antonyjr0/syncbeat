# Amazfit Music Sync — Codex implementation instructions

## Mission
Build a production-minded Flutter application for **Android and Windows** that authenticates with Spotify, imports accessible playlists and track metadata, matches tracks against **authorized downloadable audio sources**, downloads permitted audio files to a temporary staging area, and prepares them for transfer through the **official Zepp app** to the **preinstalled Music player** on the user's Amazfit Active 3 Premium. The user will listen offline on Bluetooth headphones without a phone. **Do not build a custom watch music player.**

## Important facts and constraints
- Spotify is a **metadata/playlist source only**. Spotify Web API does not provide downloadable MP3 files. Never implement Spotify stream ripping, DRM circumvention, or YouTube downloading/conversion in violation of content rights or platform terms.
- Sources must explicitly authorize downloading and the intended use. Start with Jamendo's documented API and `audiodownload_allowed`; obey licensing, API conditions and attribution. Also support user-owned, legally acquired local MP3 files. Never claim that a Spotify track has a legal audio match without verification.
- Spotify playlist API permissions, endpoints, scopes, access tiers, and quotas may change. Consult current official docs before implementing. Some playlists may not be accessible to the app; handle this visibly and gracefully. Importing the 16 supplied track IDs individually is a useful fallback for initial metadata testing.
- The Zepp app's music import flow is official, but a public API for third-party apps to upload directly into the **stock Music player** is not established. Do not claim or fake full automatic sync. First ship a reliable **manual handoff**: export/share downloaded files so the user can select them from Zepp. Research and document any legitimate Android integration separately; gate experimental automation behind explicit opt-in and capability checks.
- Never delete source files, the user's personal library, or downloaded files before a successful, user-confirmed transfer. Since transfer confirmation from Zepp may not be programmatically accessible, use a manual 'Transferred to watch' confirmation before cleaning up temporary copies. Provide a recoverable staging folder and clear cleanup controls.
- Protect credentials and tokens. The Spotify client secret was previously disclosed in conversation: **do not use it, store it, commit it, or ask for it**; advise rotating it. Use Authorization Code + PKCE for both platforms, not embedded client secrets.

## Application configuration
- Spotify Client ID (public): `1abb1e10cf8041c2957b9f748a26b8ad`
- Windows redirect URI: `http://127.0.0.1:8888/callback`
- Android redirect URI: `amazfitmusicsync://callback`
- Both redirect URIs were reportedly registered in the Spotify developer dashboard. Validate exact-match registration and current Spotify redirect URI rules before coding.
- Test playlist ID: `0j8M0X55dh5EC4fqlzy6uN`
- Initial track IDs (preserve order):
  1. `2K7bv4Q0FNNKPt4PPPCjOi`
  2. `0qYQaWV0956J7eouZaVmHn`
  3. `066ucxOm9btG4ApNim7Ohh`
  4. `7EOKcZX9TRkIs0nwWbCCbD`
  5. `1tISuPhzoKVIK3K9EDEC3E`
  6. `1BsPVfsb795RRceGK7rLSz`
  7. `3i4rci1J95OdMxer9kxjqW`
  8. `42BfRnednwP0IYXSDIPqfC`
  9. `1uwRaRWJiMiDD945IPdFbV`
  10. `3PYYiqmhooCNCGiiPTM5zS`
  11. `18NBoQ9SyURVcsPW6sP8tv`
  12. `5jT6gl92pmDlKy9689oZSX`
  13. `7L8cIUKXToCr6PV9hFoX3Q`
  14. `5E6zgNwpKQt25hBFowUIc0`
  15. `5dn2M3M51iMllhTt49eqhX`
  16. `0GuO6UjrzW2F0d2z0aOjmV`

## Working rules for Codex
1. Inspect repository contents and Flutter environment before changing files. If repository is empty, scaffold with `flutter create --platforms=android,windows .` using an appropriate project name.
2. Work incrementally, commit-ready. Keep a clear `README.md` with prerequisites, Spotify setup, legal audio-source setup, permissions, and Android/Windows run instructions.
3. Prefer maintained, cross-platform packages. Check actual package support for Windows/Android and pin compatible versions. Do not blindly assume a mobile OAuth callback library works on Windows.
4. Implement platform-specific OAuth callback handling: loopback HTTP listener for Windows (port 8888 with failure guidance) and Android intent/deep-link handling for `amazfitmusicsync://callback`. Use secure random PKCE verifier, S256 challenge, `state`, code exchange, refresh tokens, cancellation and error handling. Keep access/refresh tokens in secure storage; never log tokens.
5. Keep the public Client ID in non-secret config; never include a Spotify client secret. Add `.gitignore` rules for secrets, token stores, temporary media, generated credentials, and build artifacts.
6. Separate presentation, domain logic, API clients, persistence, platform adapters, and source integrations. Use testable abstractions and dependency injection where helpful; avoid unnecessary architectural complexity.
7. Do not infer audio availability from metadata matches alone. A match must have a valid permitted download URL or a user-selected local file. Preserve license/attribution metadata.
8. Before running destructive commands or changing existing project structure substantially, inspect and explain the impact. Avoid deleting user data.
9. After each milestone run `dart format .`, `flutter analyze`, and relevant tests; fix errors and report any environmental blockers truthfully.
10. If a step requires user account interaction (Spotify consent, Jamendo credentials, device pairing), implement the flow and document the action instead of inventing success.

## Features / milestones

### M0 — Repository foundation
- Flutter Android + Windows build targets; clear folder layout; sensible state management, navigation and theming.
- Setup wizard/status screen showing Spotify connection, audio provider availability, staging folder and Zepp handoff status.
- README and configuration example. No secrets in source control.
- Unit-test harness and a few basic widget tests.

### M1 — Spotify integration
- OAuth Authorization Code with PKCE on Android and Windows, logout and token refresh.
- Spotify API service with timeouts, pagination, rate-limit (429/Retry-After), expired token handling and actionable errors.
- List playlists available to the authenticated account, show playlist items where permissions allow, and show title, artist, album, duration, cover and Spotify ID.
- Support manual import of Spotify track links/IDs and a test screen importing the 16 IDs above. Handle unavailable, local, duplicate and restricted tracks.
- Persist playlist selection and track metadata locally without exposing sensitive account information.

### M2 — Authorized audio-source resolver
- Define `AudioSourceProvider` interface: search by track metadata, list verified downloadable candidates, show license/price/quality and provide download metadata.
- First provider: Jamendo API, using official documented endpoints, with explicit `audiodownload_allowed` checks and applicable licensing restrictions.
- Second provider: user-owned local MP3 file picker (Android and Windows) and safe metadata matching.
- Matching: normalized title/artist, optional ISRC where available, duration tolerance, version/live/remix distinctions; show confidence and require user approval for uncertain matches.
- Explicit states: matched downloadable, local match, purchase required, no authorized match, source error. Do not silently substitute different recordings.
- Download manager: progress, cancellation, retries, filename sanitization, checksums/size checks where possible, safe storage, deduplication, and disk-space estimates.
- Preserve source URL/license/attribution in a local manifest. Only download if permission is confirmed.

### M3 — Zepp handoff / storage management
- Determine and document actual audio formats and constraints supported by **Amazfit Active 3 Premium stock Music app**, using official device/Zepp documentation or user testing; do not assume arbitrary codecs or file sizes work.
- Build a staging library of supported files, with playlists, filenames and metadata. Transcode only when source license permits; never transcode Spotify protected content.
- On Android, expose staging files via appropriate storage/share APIs so they can be selected for import in Zepp; test actual usability with Zepp. Provide clear step-by-step instructions inside the app for the official import workflow.
- On Windows, export files into a chosen folder and explain that the official Zepp phone app is still needed to transfer music unless a supported transfer method is verified.
- Show progress through statuses: downloaded → ready for Zepp → user-confirmed transferred → eligible for cleanup. No automatic cleanup without explicit confirmation.
- Explore **only documented and permission-compliant** Zepp integration options. Treat full automatic transfer to the stock player as a separate feasibility spike; do not promise it.

### M4 — Polish and reliability
- Responsive Android/Windows UI, playlist selection, bulk actions, download queue, source attribution, disk usage, error recovery and accessible UI.
- Optional incremental sync based on playlist differences, but do not delete files merely because Spotify metadata changed.
- Tests for PKCE/state validation, API pagination and errors, matching false positives, download authorization, staging, and safe cleanup.
- README: platform setup, limitations, known gaps, privacy, copyright/licensing, troubleshooting, and how to rotate Spotify credentials.

## Suggested layout (adapt to actual repo)
```text
lib/
  main.dart
  app/
  config/
  features/auth/
  features/spotify/
  features/audio_sources/
  features/downloads/
  features/zepp_handoff/
  shared/
test/
README.md
AGENTS.md
```

## Acceptance criteria for initial deliverable
- Android and Windows targets build in configured environments.
- User can authenticate with Spotify using PKCE, view accessible playlists, and import the supplied 16 track IDs with truthful metadata/error reporting.
- User can search an authorized audio provider and distinguish genuine downloadable matches from unavailable tracks.
- User can download at least one explicitly permitted test audio file to a staging folder, then open/share it for the official Zepp import workflow.
- Temporary files are only removed after user confirmation; no secrets are committed.
- `flutter analyze` and tests pass, or blockers are listed with exact commands and outputs.

## Immediate Codex execution request
Begin with M0 and M1. Inspect the repository and Flutter toolchain, scaffold only what is missing, implement the Spotify PKCE flow and playlist/track retrieval, write tests, and provide precise run steps for Android and Windows. Then report what is implemented and ask for any user-side OAuth or device actions needed before moving to M2. Do not pretend M2–M4 are complete.
