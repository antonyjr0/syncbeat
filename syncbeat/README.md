# SyncBeat

Flutter app for importing Spotify playlist and track metadata in preparation
for a lawful offline-music workflow for Amazfit Active 3 Premium. Spotify is
used only as a metadata source. SyncBeat does not download Spotify audio or
transfer music directly into the watch.

## Current scope

- M0: Android and Windows targets, setup status, dashboard, local metadata cache,
	and widget/unit test harness.
- M1: Spotify Authorization Code with PKCE, secure token storage, token refresh,
	playlist pagination, playlist item retrieval, manual track ID/link import, and
	the supplied 16-track test import.
- M2: Jamendo search, configurable matching, user-selected MP3 matching, and
	app-private MP3 staging are implemented. Jamendo offline downloads are blocked
	by default pending explicit permission for this application use.
- M3-M4: Zepp handoff, transfer confirmation/cleanup workflow, sync queue, and
	broader reliability work are not implemented.

Playlist item access depends on the current Spotify API and account permissions.
Spotify can deny item access for playlists the authenticated user does not own
or collaborate on. Such errors are surfaced; SyncBeat does not claim that
restricted tracks were imported.

## Requirements

- Flutter 3.44 or later with Dart 3.12 or later.
- Windows 10 or later for the Windows desktop target.
- Android SDK and a physical Android device or emulator for Android testing.
- A Spotify Developer app with the redirect URIs below registered exactly.

## Spotify setup

The public Client ID is in `lib/config/app_config.dart`. It can be overridden
with `SPOTIFY_CLIENT_ID` in a local `config/app_config.json` based on
`config/app_config.example.json`. That local file is ignored by Git. Never add a
Spotify client secret: native and desktop clients use PKCE and have no embedded
client secret.

Register these redirect URIs in the Spotify Developer Dashboard, matching them
exactly:

- Windows: `http://127.0.0.1:8888/callback`
- Android: `amazfitmusicsync://callback`

The app requests `playlist-read-private` and `playlist-read-collaborative`.
Windows listens only on loopback port 8888; if it is occupied, close the other
process and retry. Android returns through the registered custom URI scheme.
Login times out after three minutes. A Spotify consent, network, or dashboard
action must be completed by the user; the app does not simulate success.

## Run

Run commands from this directory (`syncbeat/`):

```powershell
flutter pub get
flutter run -d windows
```

For Android, connect a device with USB debugging enabled or start an emulator,
then run:

```powershell
flutter run -d <device-id>
```

List available targets with `flutter devices`. Build commands:

```powershell
flutter build windows
flutter build apk --debug
```

The public Client ID bundled in `AppConfig` is used by default. If you create a
local `config/app_config.json` from the example, add
`--dart-define-from-file=config/app_config.json` to either run command to
override it. The web target is not an authentication target for this project.

## Authorized audio sources (M2)

Create a Jamendo application at the [Jamendo developer portal](https://devportal.jamendo.com/)
and set its public Client ID using `JAMENDO_CLIENT_ID`. The ID is not a private
secret, but the local configuration file remains ignored by Git. Search uses the
official `GET /v3.0/tracks/` API and requests the license metadata. Jamendo
results are matched by normalized title/artist and duration; ambiguous results
must be selected manually. A result is never treated as downloadable solely
because its metadata matches.

Every Jamendo candidate must pass the API's `audiodownload_allowed` flag, have a
recognized Creative Commons license and a valid Jamendo download URL. Jamendo's
published API terms also say applications must not be specifically designed for
offline access. Therefore `JAMENDO_OFFLINE_USE_AUTHORIZED` defaults to `false`
and the Jamendo download button stays disabled even when the artist allows an
API download. See the [Jamendo tracks API documentation](https://developer.jamendo.com/v3.0/tracks)
and [API terms](https://devportal.jamendo.com/api_terms_of_use). Enable it only
after obtaining explicit authorization from Jamendo for this app's offline-watch
use. The artist's download flag alone does not grant that separate permission.

The local MP3 picker reads ID3 tags and duration, falls back to
`Artist - Title.mp3`, and asks the user to confirm they have rights to use the
file offline. Selected bytes are copied into the private application support
directory under `audio_staging`; source files are never removed. The staging
writer checks the MP3 signature, sanitizes names, reports progress, supports
cancellation, enforces a size limit, records SHA-256 and writes a per-file
license/source manifest. Jamendo space figures are estimates based on a 192 kbps
MP3 bitrate; local file sizes come from the file picker. M3 handoff, recovery
controls, transfer confirmation, and cleanup are not implemented yet.

Run with the local configuration file or public dart-defines, for example:

```powershell
flutter run -d windows --dart-define-from-file=config/app_config.json
flutter run -d <device-id> --dart-define-from-file=config/app_config.json
```

## Data and Appwrite

OAuth access and refresh tokens are stored with `flutter_secure_storage`.
Playlist names, track metadata, and the selected playlist are cached locally;
Spotify tokens and account secrets are not written to the metadata cache.

Appwrite is not connected yet. The workspace does not contain the endpoint,
project/database/table IDs, document schema, or Appwrite sign-in flow from the
other application. Do not put an Appwrite server API key in this app. To reuse
that backend, first identify the existing user-authenticated session method and
the metadata collection/table fields; cloud access must be scoped to the signed
in user. Local caching works without Appwrite.

## Copyright and device limitations

Spotify Web API provides metadata, not downloadable MP3 files. Only implement
audio providers that explicitly authorize downloading and intended use.
Jamendo search checks `audiodownload_allowed` and license metadata, but offline
download stays disabled until Jamendo authorizes this application use. The local
provider only stages MP3 files selected by the user after rights confirmation.
Keep source license and attribution with any permitted download.

The official Zepp music import flow is the planned transfer path. A public API
for third-party apps to upload directly to the stock watch Music player has not
been verified. No automatic transfer or cleanup is claimed. A future staging
workflow must preserve originals and require the user's explicit transfer
confirmation before deleting temporary copies.

## Validation

```powershell
dart format .
flutter analyze
flutter test
```

Rotate any Spotify client secret that may have been disclosed previously. This
project does not use or store that secret.
