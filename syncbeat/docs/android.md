# SyncBeat Android: implementazione e prova su smartphone

## Architettura

Spotify → playlist/brani → ricerca YouTube → ranking Dart → scelta manuale →
download autorizzato → MP3 in Download/SyncBeat → schermata **MP3 locali · ascolta**.
Per il nuovo salvataggio pubblico vedere [download e verifiche](downloads.md).

Il provider conserva la stessa API Dart e gli stessi argomenti yt-dlp. Su Windows
avvia gli eseguibili già installati; su Android chiama `syncbeat/youtube` tramite
MethodChannel. EventChannel `syncbeat/youtube/events` trasporta i progressi con
ID operazione; i metadati completi necessari al matching vengono restituiti una
sola volta sul MethodChannel, evitando duplicazioni e gare tra i due canali.

Restano condivisi query generica + auto-generated, deduplicazione, massimo dieci
candidati mostrati, normalizzazione, ranking 0–100, motivazioni, ambiguità,
classificazione canali, cache, associazioni persistenti, autorizzazioni,
conversione richiesta a yt-dlp, nomi sicuri, verifica MP3, SHA-256 e manifest.
La classificazione OAC conserva il limite documentato in `youtube_matching.md`:
la verifica generica non conferma OAC; con l'output attuale OAC rimane unknown.

`MainActivity` mantiene l'embedding Flutter e il deep link Spotify esistente.
`YoutubeOperationService` esegue yt-dlp/FFmpeg fuori dal thread UI, in un servizio
foreground `dataSync` con notifica, azione Annulla e wake lock limitato. È ammessa
una sola operazione alla volta. Timeout ricerca 30 secondi, download 15 minuti;
il bridge ha un ulteriore limite di attesa. Socket timeout e retry sono limitati.
La policy nativa consente solo ricerche ytsearch, download MP3 su youtube.com e
output nelle directory private; rifiuta opzioni arbitrarie e path esterni.

Dal 4 novembre la ricerca usa `--flat-playlist`: legge i metadati delle pagine
di ricerca senza estrarre ogni singolo video. Conserva entrambe le query e non
inizializza FFmpeg per cercare. Socket timeout 8 secondi e un retry per ricerca;
i download mantengono i propri limiti. [Misure e verifica](youtube-search-performance.md).

I nuovi MP3 YouTube sono pubblicati in MediaStore Downloads, con percorso relativo
`Download/SyncBeat/` e URI `content://`. Su Android 7–9 il selettore SAF chiede
di scegliere Download nella memoria interna. Nessun permesso generale di memoria.
I file pubblici rimangono nel telefono; la disinstallazione elimina comunque
token, associazioni e indice privato Android. Aggiornare l'APK senza disinstallare.
I vecchi MP3, Jamendo e le copie locali restano in
`getApplicationSupportDirectory()/audio_staging` e non vengono spostati o eliminati.

La libreria locale elenca gli MP3 pubblicati e quelli nello staging e li riproduce con
MediaPlayer nativo, con posizione e comando Stop, anche senza rete. Su Windows
apre l'MP3 con l'applicazione associata. Non è una libreria musicale completa:
non aggiunge coda, seek, controlli Bluetooth o MediaSession sulla schermata blocco.
La riproduzione termina uscendo dalla schermata della libreria o distruggendo
l'Activity; non è un servizio di riproduzione audio in background.

## Dipendenze e compatibilità

Artefatti fissati da Maven Central:

```
io.github.junkfood02.youtubedl-android:library:0.18.1
io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1
```

Sono la versione stable pubblicata disponibile al controllo. I metadati Maven
riportano aggiornamento 16 novembre 2025: non va assunto che gli extractor inclusi
restino aggiornati rispetto ai cambiamenti di YouTube. La libreria include
Python e QuickJS, oltre al runtime yt-dlp; FFmpeg è inizializzato dal modulo nativo.
Non servono root, Termux, Python o FFmpeg installati dall'utente sul telefono.
Aria2 non è incluso perché non necessario.

Requisito minimo Android 7/API 24. Flutter costruisce le ABI armeabi-v7a,
arm64-v8a e x86_64. `extractNativeLibs=true` e packaging legacy sono impostati
perché la libreria deve eseguire i runtime estratti. Non è una certificazione
su tutte le versioni Android/ABI o su dispositivi con pagine di memoria 16 KiB:
tali combinazioni richiedono test nativi sul dispositivo.

Nel dialogo YouTube Android, **Aggiorna motore YouTube** usa l'updater stable
incluso nella libreria. È un aggiornamento in-app avviato dall'utente, non
un'installazione esterna. In caso di problemi di rete il messaggio è visibile.
L'updater non è un processo yt-dlp cancellabile: Annulla/timeout ne segnano
l'esito ma non garantiscono di interrompere subito una richiesta HTTP già attiva.
Un aggiornamento del motore non aggiorna automaticamente le librerie native.

Il progetto usa Java 17 per una dipendenza esistente (`haudiotagger`), mentre
Gradle può avviarsi con il JBR 21 di Android Studio. Su questa macchina è stato
installato un JDK 17 portabile in `tools/android-reference/jdk17/`.
Il launcher Windows `android/gradlew.bat` rileva automaticamente il JDK portabile
in questa cartella, quindi è sufficiente `flutter build apk`. Un valore esplicito
di `SYNCBEAT_JDK17` ha precedenza. Per indicare un'altra installazione:

```powershell
$env:SYNCBEAT_JDK17 = (Get-ChildItem tools/android-reference/jdk17 -Directory | Select-Object -First 1).FullName
flutter build apk --debug
```

Su un'altra macchina SYNCBEAT_JDK17 deve indicare la propria installazione JDK 17.
Flutter doctor segnala qui cmdline-tools Android mancanti; SDK/platform/build-tools
e una licenza SDK erano già presenti. Per configurare da zero un ambiente usare
Android Studio, installare cmdline-tools e accettare personalmente le licenze.
Non sono state accettate nuove licenze SDK automaticamente.

## Licenze

youtubedl-android e il modulo FFmpeg sono GPL-3.0. La combinazione APK distribuita
deve rispettare gli obblighi GPL, compresi sorgenti corrispondenti e informazioni
di build; la licenza MIT dei file originali del progetto non elimina tali obblighi.
Il testo GPL e i riferimenti ai componenti sono inclusi negli asset Android,
consultabili dal pulsante **Licenze** nella libreria MP3. Prima di una distribuzione
pubblica serve completare l'inventario delle licenze/transitive dei binari inclusi
e consegnare i sorgenti corrispondenti. Questo APK è una build di sviluppo.

Fonti primarie:

- https://github.com/yausername/youtubedl-android/tree/0.18.1
- https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/library/maven-metadata.xml
- https://github.com/yausername/youtubedl-android/blob/0.18.1/BUILD_FFMPEG.md
- https://github.com/yausername/youtubedl-android/blob/0.18.1/LICENSE
- https://developer.android.com/develop/background-work/services/fgs/service-types#data-sync

## Background, annullamento e limiti

Il servizio consente al processo nativo di continuare quando l'app passa in
background. La notifica offre Annulla; dal dialogo funziona anche Annulla operazione.
Android 13+ richiede il consenso alle notifiche; se negato, il servizio può essere
visibile solo nella gestione attività del sistema. Chiudere il dialogo annulla
l'operazione, come su Windows; premere Home la lascia in corso.

Non è una coda persistente WorkManager: force-stop, morte del processo, riavvio
o limitazioni del produttore possono interrompere il lavoro. Non è implementata
la ripresa automatica dopo questi eventi. Il passaggio finale in Download è
eseguito da Dart dopo la conversione: non è garantito dopo la morte dell'engine.
Solo i temporanei dell'operazione vengono rimossi nei percorsi di errore gestiti;
una terminazione forzata può lasciare temporanei privati, senza MP3 finale valido.

La cancellazione usa `destroyProcessById` della libreria: l'arresto effettivo dei
processi figli FFmpeg va provato su telefono. L'implementazione upstream usa
strumenti shell per i figli, quindi non si promette cancellazione istantanea su
tutti i firmware Android. Non vengono aggirate restrizioni del sistema o YouTube.

Nessun cookie, segreto client, bypass DRM, proxy geografico o opzione di elusione
viene introdotto. La scelta di un video e lo stato ufficiale del canale non
autorizzano il download. Restano obbligatorie le conferme e il riferimento dei
permessi già presenti in SyncBeat. Nessun invio a Zepp/Amazfit.

## Installazione su smartphone reale

1. Sul telefono abilita Opzioni sviluppatore e Debug USB, collegalo al PC e
   autorizza la chiave RSA. Non disinstallare un'installazione esistente.
2. Dalla directory del progetto verifica e installa:

   ```powershell
   & "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" devices -l
   & "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

   In alternativa trasferisci l'APK sul telefono e autorizza l'installazione
   dalla specifica applicazione usata per aprirlo. Non servono runtime esterni.
3. Apri SyncBeat e collega Spotify. Controlla che il browser torni all'app tramite
   `amazfitmusicsync://callback`, già registrato nella configurazione Spotify.
4. Importa playlist e/o i 16 ID di prova. Cerca su YouTube un brano, incluso
   VELENO. Controlla titoli, artisti, durata, ragioni, Topic/verifica/OAC unknown.
5. Apri/ascolta nel browser, scegli manualmente, salva e riavvia per verificare
   la persistenza dell'associazione.
6. Per un video con permessi espliciti, documenta l'autorizzazione, conferma
   download e conversione/uso offline e avvia Scarica e converti MP3.
7. Consenti le notifiche. Premi Home o spegni lo schermo; verifica notifica,
   completamento al rientro e file finale. Ripeti annullando da notifica e dialogo.
8. Apri **MP3 locali · ascolta**, riproduci e ferma il file; riprova senza rete.
9. Prova rete assente, URL non accessibile, aggiornamento motore, permessi
   mancanti e un file audio corrotto: verificare errori visibili e nessun falso
   completamento. Prova anche MP3 locale e Jamendo per regressioni.
10. Force-stop/riavvio sono test separati: il lavoro non deve essere dichiarato
    ripreso automaticamente. Raccogli eventuali errori con `adb logcat` senza
    condividere token Spotify o dati personali.

## Verifiche automatiche

Comandi dalla directory del progetto:

```powershell
flutter analyze
flutter test
flutter build apk --debug
flutter build windows
Push-Location android
.\gradlew.bat :app:testDebugUnitTest --console=plain
Pop-Location
```

I test Dart del bridge simulano MethodChannel/EventChannel, non yt-dlp reale su
Android. I test JVM nativi verificano la policy di comandi, timeout e file privati.
La suite condivisa verifica ranking, cache, VELENO, associazioni e staging.
Compilazione e test JVM **non provano funzionamento su dispositivo fisico**.
Al momento dell'implementazione `adb devices -l` non elenca dispositivi Android.

Esiti finali del 3 novembre 2026:

- `flutter analyze`: nessun problema.
- `flutter test --reporter expanded`: 79 test superati.
- `:app:testDebugUnitTest`: 4 test JVM, nessun errore o fallimento.
- `flutter build apk --debug`: riuscita; APK universale circa 258 MiB, in
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter build windows`: riuscita.
- `git diff --check`: nessun errore.

L'APK finale contiene le tre ABI indicate e gli asset delle licenze. Nel controllo
statico degli ELF ARM64, Python, QuickJS, FFmpeg e FFprobe hanno allineamento
minimo 16384; il pacchetto FFmpeg contiene libmp3lame. Questo controllo non prova
installazione, conversione o riproduzione su un dispositivo 16 KiB.

Restano avvisi Gradle dei plugin preesistenti `appwrite`/`flutter_web_auth_2`
sull'adozione futura di Built-in Kotlin e deprecazioni prima di Gradle 10.
Non sono stati aggiornati questi plugin per evitare modifiche estranee al flusso.

File principali introdotti/modificati: `android_youtube_bridge.dart`,
`local_audio_library.dart`, `youtube_provider.dart`, `youtube_match_dialog.dart`,
`app.dart`; `MainActivity.kt`, `YoutubeOperationService.kt`,
`YoutubeRequestPolicy.kt`, manifest, Gradle e asset licenze; test Dart del bridge,
test Kotlin della policy, README e questa procedura. Il codice di autenticazione
Spotify e quello del provider Jamendo non sono stati modificati.
