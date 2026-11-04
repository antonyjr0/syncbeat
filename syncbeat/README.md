# SyncBeat

Flutter app for importing Spotify playlist and track metadata in preparation
for a lawful offline-music workflow for Amazfit Active 3 Premium. Spotify is
used only as a metadata source. SyncBeat does not download Spotify audio or
transfer music directly into the watch.

## Current scope

Latest [Windows/Android audit and test checklist](docs/audit-2026-11-03.md):
baseline tests/builds pass, but supplemental probes expose open OAuth/staging
defects. Android physical-device validation remains pending.

- M0: Android and Windows targets, setup status, dashboard, local metadata cache,
	and widget/unit test harness.
- M1: Spotify Authorization Code with PKCE, secure token storage, token refresh,
	playlist pagination, playlist item retrieval, manual track ID/link import, and
	the supplied 16-track test import.
- M2: Jamendo search, configurable matching, user-selected MP3 matching, and
	app-private MP3 staging are implemented. Jamendo offline downloads are blocked
	by default pending explicit permission for this application use.
- YouTube: primary search option on Windows and Android through yt-dlp, manual
  association, ranked candidates and authorized MP3 conversion through FFmpeg.
  Local MP3 files can be listed and played from the application.
- M3-M4: Zepp handoff, transfer confirmation/cleanup workflow, sync queue, and
	broader reliability work are not implemented.

Playlist item access depends on the current Spotify API and account permissions.
Spotify can deny item access for playlists the authenticated user does not own
or collaborate on. Such errors are surfaced; SyncBeat does not claim that
restricted tracks were imported.

## Requirements

Android YouTube support and local playback are implemented through the native
youtubedl-android/FFmpeg bridge (API 24+). See [Android setup and physical-device
test procedure](docs/android.md), including runtime/license/background limitations.

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

## YouTube on Windows

The local `tools/` directory contains installed yt-dlp, FFmpeg/FFprobe and Deno.
The Windows build copies these tools next to the application in `tools/`; run
the entire Release folder, rather than moving only `syncbeat.exe`. These large
third-party binaries and downloaded test metadata are excluded from Git.
The app discovers tools beside its executable, then in the working directory,
then the PATH. Overrides are `--dart-define=YT_DLP_PATH=C:\path\yt-dlp.exe`
and `--dart-define=FFMPEG_LOCATION=C:\path\ffmpeg-bin`.

Search combines `ytsearch10:artist title` and
`ytsearch5:artist title auto-generated`, with full per-video metadata. Up to 15
internal candidates are deduplicated and ranked before displaying the best ten.
This also discovers distributed recordings omitted by the general search.
Unavailable videos can reduce the count below ten. Network errors and missing tools appear
in the dialog; search can be cancelled or retried. No YouTube login, cookies,
DRM bypass, region bypass or restriction bypass is configured. The tool ignores
the user's yt-dlp configuration. A search times out after three minutes and a
download/conversion after fifteen minutes; cancellation stops the process tree,
including FFmpeg on Windows.

Ranking is normalized to 0?100. Default configurable weights are title 35,
all Spotify artists/collaborators 25, duration 20, version 12, provenance 6,
generic verification 2. Missing values earn no points. Version mismatches and
incompatible duration/title/artist limit the score; views are never used.
Scores within 3 points are flagged as ambiguous, without automatic selection.
See [the matching report](docs/youtube_matching.md) for channel classification,
exact scoring, cache behavior and OAC limitations.

The highest candidate is highlighted but never automatically selected. Open
videos in the browser, choose a radio button and explicitly save the association.
The app stores the Spotify ID and chosen video metadata locally in preferences,
independently of downloaded files. Reopening restores the saved association and
its confirmations. New search results are never automatically selected; search
and explicitly save a replacement to change the association.

From an imported track, press **YouTube / MP3**, search, select a video manually
and save the association. **Scarica MP3** stays in the dialog footer after selection.
See [public Downloads storage, verification results and device checklist](docs/downloads.md).

Download requires separate confirmation
of rights/platform download permission and conversion/offline-use permission.
The app records this user attestation in the download manifest; it cannot verify
the legal validity of the document. Search, a matching title or a Creative
Commons label alone never enables downloading. FFmpeg converts permitted audio
to MP3 at 192 kbps. New YouTube MP3s are validated privately and then published
in the real Windows Downloads/SyncBeat folder or Android MediaStore Downloads
at Download/SyncBeat/. Size and SHA-256 are checked; names avoid overwrites.
Source URL and attribution stay in a manifest. Previous private files remain
readable and are not moved or deleted. Jamendo/local import keep their existing
staging flow. This does not implement M3 or transfer to Zepp.

Implementation references: [yt-dlp options and Windows releases](https://github.com/yt-dlp/yt-dlp),
[JavaScript runtime setup](https://github.com/yt-dlp/yt-dlp/wiki/EJS),
[FFmpeg Windows builds](https://github.com/yt-dlp/FFmpeg-Builds).

### Test with the 16 Spotify tracks

1. Run `build\windows\x64\runner\Release\syncbeat.exe` or `flutter run -d windows`.
2. Connect Spotify with the existing PKCE login. Click **Importa i 16 ID test**.
   Wait for metadata; any inaccessible tracks are reported individually.
3. For each imported track, open its audio-source search, choose
   **YouTube · ricerca principale**, then **Cerca su YouTube**.
4. Check the up-to-ten results: title, channel, duration, thumbnail, URL and score.
   The best candidate is highlighted and no radio button is preselected.
5. Use **Apri e ascolta nel browser**. Choose the right recording, including a
   lower-ranked result if needed, then **Salva associazione Spotify → YouTube**.
6. Close/reopen the dialog and restart the app to verify persistence. Search
   again and save another result to verify replacement for that Spotify ID.
7. Try **Annulla operazione** during search. For a video you have explicit
   permission to download/convert, confirm both
   permissions and test **Scarica MP3**, progress and cancellation.
   An association itself does not authorize downloading the 16 Spotify songs.
8. Check that **Cerca su Jamendo** and **Scegli MP3 locale** still work.

Automatic tests cover ranking/version penalties, persistence/replacement,
explicit UI selection, blocked unauthorized download, staging progress/manifests,
conversion errors and cancellation. A real ten-result YouTube metadata search was
also verified; downloading the supplied commercial tracks is not part of that
smoke test.

## Data and Appwrite

Reliability fixes and validation: [4 November 2026](docs/critical-fixes-2026-11-04.md).

YouTube download confirmations are saved locally with each Spotify/video association.
Reopening restores the saved selection and confirmations. Choosing another video
requires new confirmations. Unchecking a saved confirmation persists its revocation.
Older selections without confirmations require explicit approval.


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
