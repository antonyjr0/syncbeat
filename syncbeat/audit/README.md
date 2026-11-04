# Audit ripetibile

Eseguire dalla directory Flutter del progetto. Le prove qui sono fuori da `test/`
per distinguere la baseline dai controlli diagnostici che espongono difetti noti.
Non sono nuove funzionalità dell'app. Dettagli e checklist: `docs/audit-2026-11-03.md`.

```powershell
flutter analyze
flutter test
flutter build windows
$env:SYNCBEAT_JDK17 = (Get-ChildItem tools/android-reference/jdk17 -Directory | Select-Object -First 1).FullName
flutter build apk --debug
flutter test audit/authorized_media_test.dart --dart-define=AUDIT_BUNDLED_TOOLS=true
flutter test audit/youtube_live_test.dart
flutter test audit/known_failures_test.dart
```

Aggiornamento del 4 novembre: l'ultima suite ora passa tutte e tre le prove:
rilascio porta OAuth dopo fallimento browser, rifiuto cache corrotta e rifiuto
stream troncati. Dettagli: [correzioni](../docs/critical-fixes-2026-11-04.md).
I test HTTP/codec e YouTube sono Windows-only; richiedono i runtime già installati.
La ricerca live usa la rete ma non scarica audio YouTube. Il test media genera
un tono sintetico, lo serve solo su loopback e ne autorizza esplicitamente
download, conversione, copia e uso offline. Usa yt-dlp/FFmpeg reali, non mock.

Artefatti locali: `tools/audit/authorized-media/authorized-tone.wav`,
`converted.mp3`, `PERMISSION.txt`, `evidence.json` e staging separati per esecuzione.
Gli artefatti non vengono inseriti nel controllo versione. Il download HTTP del
tono non è una prova dell'estrazione audio YouTube né una corrispondenza Spotify.

È riproducibile anche un difetto del percorso FFmpeg di sviluppo:

```powershell
flutter test audit/authorized_media_test.dart
flutter test audit/authorized_media_test.dart --dart-define=AUDIT_FFMPEG_FILE=true
```

Con la cartella `tools/ffmpeg/` presente, il primo comando fallisce nella discovery
FFmpeg di yt-dlp; il secondo passa usando `ffmpeg.exe` esplicitamente. Il runtime
della build Release passa senza workaround perché non contiene quella cartella.
