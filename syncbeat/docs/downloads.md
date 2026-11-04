# Download MP3 pubblico — 3 novembre 2026

## Diagnosi e interfaccia

Il downloader YouTube e la conversione erano già implementati. Il comando era
visibile soltanto dopo la scelta di un risultato, al termine di tutta la lista
scorrevole, dopo riferimento e checkbox dei permessi. Dalla playlist si passava
inoltre attraverso un'icona generica e un secondo dialogo. Il file finale era
salvato nello staging privato, poco raggiungibile sul telefono.

Ora ogni brano importato mostra **YouTube / MP3**, che apre direttamente la
ricerca. Il percorso precedente per Jamendo e MP3 locali rimane disponibile.
La scelta resta manuale: il miglior candidato non è preselezionato.
Selezionando un risultato, il pannello della scelta viene portato in vista,
prima dei risultati; **Scarica MP3** resta nel piè di pagina del dialogo.
Il comando si abilita dopo **Salva associazione Spotify → YouTube**, riferimento
di almeno 12 caratteri e le due conferme di autorizzazione esistenti.
La scelta di un video diverso azzera i permessi inseriti.

Le fasi mostrate sono ricerca, download, conversione MP3, verifica/salvataggio.
La percentuale appare quando è disponibile un totale; le altre fasi sono
indeterminate. Non è una percentuale complessiva di tutte le fasi.
**Annulla operazione** usa il token esistente anche nella pubblicazione.
Alla fine compaiono percorso/URI, **Apri file** e **Apri cartella**.

## Dove si trovano i file

**Windows:** `getDownloadsDirectory()` usa l'implementazione Windows di
path_provider, che richiama `SHGetKnownFolderPath(FOLDERID_Downloads)`.
Non viene ricostruito il percorso da USERPROFILE. È quindi rispettato il
percorso Download registrato da Windows, compresi i reindirizzamenti.
La sottocartella `SyncBeat` viene creata quando serve.
Su questo PC il percorso effettivamente verificato è:

```
C:\Users\Dev04\Downloads\SyncBeat\
```

Aprire **Esplora file → Download/Scaricati → SyncBeat**, oppure **Apri cartella**.
Accanto a ogni nuovo MP3 Windows si trova il manifest `.mp3.json` con sorgente,
associazione Spotify, autorizzazione dichiarata, dimensione e SHA-256.
Non eliminare il manifest se si vuole mantenere il file nell'indice della libreria.

**Android 10+ (API 29+), incluso lo Xiaomi:** `MediaStore.Downloads`, MIME
`audio/mpeg`, `RELATIVE_PATH=Download/SyncBeat/`. Nessuna cartella Download
privata e nessun MANAGE_EXTERNAL_STORAGE, READ_MEDIA_AUDIO o permesso generale.
Il file è normalmente raggiungibile da **Gestione file → Memoria interna →
Download → SyncBeat**. Il codice usa l'URI `content://`, non un percorso fisico
presunto. I manifest sono conservati nelle preferenze private native insieme
all'URI, indipendentemente dalle associazioni Spotify–YouTube.

**Apri file** concede al lettore esterno il permesso temporaneo di lettura.
**Apri cartella** apre la schermata Download del sistema: alcuni file manager
non supportano questo intent; in quel caso viene mostrato un errore e si può
aprire Gestione file manualmente. Non si garantisce l'apertura direttamente
della sottocartella su tutti i firmware.

**Android 7–9 (API 24–28):** MediaStore Downloads non esiste. Il fallback SAF
chiede di selezionare **Download nella memoria interna**, crea `SyncBeat` e
conserva il permesso sulla cartella scelta. Una selezione diversa è rifiutata.
Il temporaneo pubblico ha estensione `.part`, rinominata `.mp3` dopo verifica;
su queste API non esiste l'equivalente di IS_PENDING e il temporaneo può essere
visibile al gestore file durante la copia.

I file pubblici non richiedono che SyncBeat sia aperto. Disinstallare Android
lascia gli MP3 pubblici ma elimina token, associazioni e indice privato: per
aggiornare usare l'installazione sopra l'app esistente, senza disinstallazione.
I vecchi download privati e i flussi Jamendo/importazione MP3 locale non sono
migrati, spostati o eliminati automaticamente; rimangono riproducibili.

## Pubblicazione e integrità

Viene riutilizzato `YoutubeDownloader`, con yt-dlp e FFmpeg esistenti, senza un
secondo downloader. La conversione è privata. Lo staging controlla il totale
previsto, limite 120 MiB, firma e SHA-256, scrive prima `.part` e ricontrolla il
contenuto dei file esistenti prima di riutilizzarli.

Prima della pubblicazione Windows, FFprobe deve identificare un solo stream
MP3 e FFmpeg deve decodificarlo senza errori. La copia pubblica viene riletta
con controllo dimensione/hash; il manifest precede la rinomina finale del file.
Android verifica formato MP3 e presenza di frame tramite MediaExtractor,
copia in un elemento MediaStore con IS_PENDING=1, chiude e rilegge la copia,
controlla dimensione/hash, registra il manifest e solo dopo azzera IS_PENDING.
MediaExtractor non equivale a una decodifica completa di tutti i campioni.
Gli errori gestiti e l'annullamento eliminano soltanto i temporanei/elementi
creati da quell'operazione. I nomi sono sanitizzati e hanno suffissi univoci.

La libreria elenca i nuovi manifest pubblici validi e i vecchi MP3 privati.
Un download già integro per lo stesso provider/video viene riutilizzato.
Alla ricarica, file cancellati o con hash/dimensione cambiati non vengono
mostrati né considerati duplicati validi. Su Android MediaPlayer accetta anche
gli URI pubblicati; su Windows viene aperto il lettore associato.
Le associazioni Spotify–YouTube conservano lo stesso formato e le stesse chiavi.

L'autorizzazione resta una dichiarazione dell'utente: l'app non verifica
legalmente il documento. I 16 ID Spotify servono per metadati/matching e non
costituiscono un'autorizzazione al download. Nessun bypass DRM/restrizioni.

## Verifiche eseguite

| Verifica | Esito |
| --- | --- |
| flutter analyze | Nessun problema |
| flutter test | 108 superati, 0 falliti, nessuno saltato su questo PC |
| flutter build windows | Riuscita |
| flutter build apk --debug | Riuscita |
| :app:testDebugUnitTest --rerun | 13 superati, 0 falliti, nessuno saltato |
| audit/public_audio_test.dart | 1 superato: pubblicazione in Download Windows reale, FFmpeg e rilettura libreria |
| audit/authorized_media_test.dart con AUDIT_BUNDLED_TOOLS=true | 1 superato: download HTTP locale del tono autorizzato con yt-dlp del bundle, conversione e decodifica FFmpeg |

I test aggiunti coprono pulsante e gate dei permessi, accesso dalla playlist,
API Known Folder e percorso reindirizzato simulato, conversione valida/non valida,
pubblicazione/manifest, cancellazioni esterne, errori di scrittura, riutilizzo dei
duplicati e riproduzione tramite URI con bridge simulato. I test JVM coprono
la transazione usata dall'adapter MediaStore: output pending, lettura di verifica,
commit, rollback, sorgente corta, destinazione troncata, errore e annullamento.
Il ContentResolver e il MediaPlayer reali Android non sono stati eseguiti.

Il tono di test è in `test/fixtures/authorized-tone.mp3`, con autorizzazione CC0
nel file LICENSE accanto. È un segnale sintetico 440 Hz di circa 0,2 secondi,
non una registrazione commerciale. È stata lasciata una copia di prova in
Download/SyncBeat; dettagli in `tools/public-audio-checks/real-downloads.json`.
I log dei comandi sono in `tools/public-audio-checks/`.

ADB non rileva telefoni collegati. Installazione, MediaStore, selettore SAF,
ascolto umano, pulsanti del file manager e flusso completo Spotify–YouTube su
Xiaomi rimangono da provare realmente. La compilazione non ne è prova.
Restano gli avvisi preesistenti KGP dei plugin Appwrite/flutter_web_auth_2 e
le deprecazioni Gradle. Nessuna nuova dipendenza nativa/manuale è stata aggiunta;
FFmpeg/FFprobe/yt-dlp Windows erano già installati, Android li include già.
L'APK è debug e non costituisce una distribuzione pubblica pronta.

Non esiste una coda persistente con ripresa dopo force-stop/morte del processo.
Il servizio yt-dlp esistente e il worker di pubblicazione non garantiscono il
completamento dopo una terminazione forzata. Possono restare temporanei privati
o elementi pending invisibili; su API 24–28 può rimanere un `.part` SAF.
Non è stata aggiunta pulizia indiscriminata dei file dell'utente.

## Checklist Windows

1. Avviare la nuova build, oppure `flutter run -d windows` dalla cartella Flutter.
   Aprire login Spotify se necessario; le credenziali non sono cambiate.
2. Selezionare una playlist e **Carica brani**, oppure importare i 16 ID.
   Ogni brano deve mostrare **YouTube / MP3**; eventuali errori Spotify rimangono
   visibili nel flusso esistente.
3. Premere **YouTube / MP3 → Cerca su YouTube**. Attendere fino a 10 risultati
   ordinati. Nessun radio deve risultare selezionato automaticamente.
4. Aprire/ascoltare i candidati nel browser e scegliere manualmente quello
   corretto. Il pannello della scelta deve andare in vista e **Scarica MP3**
   deve apparire in fondo alla finestra, ancora disabilitato.
5. Salvare l'associazione. Riaprendo il dialogo si deve ritrovare la scelta
   salvata; toccarla è una scelta esplicita, non una selezione automatica.
6. Solo per un contenuto per cui si possiedono davvero i permessi richiesti,
   inserire il riferimento e confermare entrambe le caselle. Il pulsante deve
   abilitarsi; togliendo una conferma deve disabilitarsi.
7. Avviare il download. Controllare fasi, percentuale quando disponibile e
   **Annulla operazione**. Su un secondo tentativo autorizzato completare il
   lavoro: devono apparire nome, percorso, **Apri file**, **Apri cartella**.
8. Aprire la cartella e verificare MP3 più manifest, senza `.part` definitivo.
   **Apri file** deve aprire il lettore; ascoltare davvero l'audio.
   La copia sintetica già pubblicata consente un controllo del lettore senza
   scaricare alcun brano commerciale e senza passare per YouTube.
9. Aprire **MP3 locali · ascolta** e ricaricare. Il nuovo file deve comparire
   una sola volta e riprodursi. Ripetere lo stesso download: viene riutilizzato.
10. Eliminare soltanto il proprio tono di prova da Esplora file, ricaricare la
    libreria e verificare che sparisca. Non usare brani personali per prove distruttive.

## Checklist Xiaomi Android

1. Copiare `build/app/outputs/flutter-apk/app-debug.apk` sul telefono e aprirlo
   per aggiornare SyncBeat senza disinstallare. Se richiesto, consentire al solo
   gestore file di installare questa build. In alternativa, con debug USB e PC
   autorizzato: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
   yt-dlp e FFmpeg sono inclusi; non servono root, Termux o installazioni esterne.
2. Aprire SyncBeat, provare Spotify/deep link, caricare playlist o importare i
   16 ID. Verificare il layout verticale e il pulsante **YouTube / MP3**.
3. Ripetere i passaggi 3–7 Windows. Il pulsante download deve restare nel piè
   di pagina anche scorrendo i risultati. La presenza del miglior candidato
   non deve selezionarlo. La notifica esistente permette di seguire yt-dlp.
4. Sullo Xiaomi recente non deve comparire una richiesta di accesso generale
   alla memoria. Dopo completamento aprire **Gestione file → Memoria interna →
   Download → SyncBeat**, anche dopo aver chiuso SyncBeat. Il file deve esserci
   con il nome comunicato dall'app e riprodursi con un lettore del telefono.
5. Verificare **Apri file**. Provare **Apri cartella**; se il firmware non offre
   l'azione, usare il percorso manuale e annotare il messaggio mostrato.
6. Nella libreria SyncBeat premere Riproduci, ascoltare davvero, controllare
   posizione/durata e Stop. Attivare modalità aereo e riprovare lo stesso MP3.
7. Ripetere il download: una sola voce. Eliminare soltanto un proprio file di
   prova tramite Gestione file e premere Aggiorna: la voce deve sparire.
8. Provare annullamento durante il trasferimento e durante il salvataggio:
   nessun MP3 incompleto deve essere visibile. Per API 24–28 serve un dispositivo
   separato/emulatore: scegliere Download nel SAF e controllare il fallback.
9. Per provare solamente i lettori senza permessi su video commerciali, copiare
   il tono CC0 dal PC al telefono e aprirlo da Gestione file. Questo controllo
   non prova MediaStore né il download YouTube di SyncBeat.

Un video personale pubblicato su YouTube è utilizzabile per il test completo
solo se anche i permessi della piattaforma coprono il download con questi mezzi.
Se manca un contenuto con tali permessi, fermarsi alla selezione e usare i test
sintetici per i componenti: non dichiarare verificato il flusso YouTube completo.

## File di questo intervento

- `lib/app.dart`: accesso diretto YouTube/MP3 dal brano.
- `youtube_match_dialog.dart`: pannello scelta, pulsante fisso, fasi, aperture finali.
- `youtube_downloader.dart`: notifiche fase e progressi postprocessing, stesso downloader.
- `youtube_provider.dart`: percorso esplicito ffmpeg.exe, evita collisioni con cartelle omonime.
- `public_audio_storage.dart`: nuova pubblicazione, verifica, indice, aperture.
- `staging_storage.dart`: lunghezza prevista, hash duplicati, temporanei `.part`.
- `local_audio_library.dart`: file pubblici/legacy e riproduzione URI.
- `MainActivity.kt`, `PublicAudioBridge.kt`, `PublicAudioTransaction.kt`: bridge,
  MediaStore/SAF, transazione e URI per MediaPlayer.
- `pubspec.yaml`: dipendenze di test per interfaccia path_provider e API Windows.
- Test Dart: `public_audio_storage_test.dart`, `local_audio_library_test.dart`,
  `youtube_dialog_test.dart`, `youtube_downloader_test.dart`, `responsive_layout_test.dart`.
- Test Kotlin: `PublicAudioPolicyTest.kt`, `PublicAudioTransactionTest.kt`.
- Fixture audio e licenza, `audit/public_audio_test.dart`, README e documentazione.

Non sono stati cambiati OAuth Spotify, API playlist/importazione, ranking,
classificazione canali, formato associazioni o autorizzazioni Jamendo.
Nessun trasferimento Zepp/Amazfit è stato implementato.

Riferimenti: [MediaStore e file condivisi](https://developer.android.com/training/data-storage/shared/media),
[Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files).
