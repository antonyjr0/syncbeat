# Download Android: correzione del 4 novembre 2026

## Riproduzione sullo Xiaomi 15T

Premendo Scarica MP3, il callback Dart partiva, salvava le conferme e arrivava
al bridge Android. `YoutubeRequestPolicy.requirePrivate` rifiutava il percorso
temporaneo prima di avviare yt-dlp, con il messaggio:

> YouTube Android: File esterno alla directory applicativa

L'errore era gestito ma poteva restare fuori dalla porzione visibile del dialogo,
dando l'impressione che il pulsante non facesse nulla. I log originali non
tracciavano il percorso gestito dell'errore; gli errori grafici BLAST osservati
non dimostravano la causa del download rifiutato.

## Modifica

Su Android il downloader crea ora la propria sottocartella temporanea dentro
`getTemporaryDirectory()` di path_provider, corrispondente alla cache privata
Android. Non usa più `Directory.systemTemp`, che non garantisce uno dei due
percorsi files/cache consentiti dalla policy. I controlli nativi su traversal,
percorsi esterni e output privato restano invariati.

Durante preparazione, errore e completamento il dialogo rende visibile il
pannello di stato. Le fasi distinguono controllo dei file esistenti,
preparazione temporanei, download e pubblicazione. Il tracciamento diagnostico
registra fasi e tipo dell'errore, senza URL di download, argomenti dei comandi,
credenziali o token.

## Verifica

- 125 test Flutter superati; il nuovo caso controlla che il downloader usi la
  cache fornita, elimini soltanto la propria sottocartella e preservi altri file.
- Il test del dialogo verifica che un errore sia visibile e il pulsante permetta
  un nuovo tentativo.
- `flutter analyze --no-pub`: nessun problema.
- APK release compilato e installato sullo Xiaomi 15T con `adb install -r`,
  conservando i dati dell'app.
- Prova reale sullo Xiaomi 15T: il nuovo tentativo supera la policy nativa,
  avvia il servizio, completa yt-dlp in circa 20,7 secondi e passa alla verifica
  e pubblicazione in Download/SyncBeat. L'utente conferma che il file è stato
  scaricato correttamente. Le conferme già salvate sono state mantenute.

Evidenza locale della diagnosi: `tools/phone-download-diagnostic.log` e
`tools/phone-download-error.png`; prova della correzione:
`tools/phone-download-cache-fix.log`.
