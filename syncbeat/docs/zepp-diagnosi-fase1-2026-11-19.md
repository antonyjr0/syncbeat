# Diagnosi revoca → invio, 19 novembre 2026

Incrementi locali 1.1–1.3 della roadmap `syncbeat-roadmap-incrementale-2026-11-19-041f90c9.md.txt`, indicata dall'utente come riferimento. Il checkpoint sul telefono del punto 1.4 è stato eseguito e ha isolato un blocco preliminare nel bootstrap. Il resoconto della prova è riportato in fondo.

La lettura del codice ha individuato due percorsi da osservare durante la riproduzione. Prima di questo incremento `adbStatus` richiedeva un ripristino quando il worker risultava libero. Inoltre un errore nel `finally` di `testCycle` poteva coprire l'errore di `begin`. La presenza di questi percorsi nel codice richiede un riscontro temporale durante la prova per attribuire loro il guasto riferito.

La specifica `syncbeat-specifica-codex-2026-11-19.md` citata dalla roadmap è assente dal workspace e dai file forniti. L'elenco delle cinque cause contenuto in quella specifica resta da confrontare con l'esito della prova.

## Strumentazione disponibile

- Le righe con prefisso `SyncBeatZeppDiag` registrano codici di fase, timestamp Unix in millisecondi e, sul lato Android, tempo monotono in millisecondi. Il codice Android usa il tag logcat `SyncBeatZeppDiag`, mentre le righe Dart passano attraverso il tag `flutter`. L'ID numerico della richiesta collega scrittura Dart e gestione server. I nuovi log omettono payload, percorsi audio, titoli, indirizzi, chiavi e codici di abbinamento.
- Il dialogo registra apertura, lifecycle, chiusura e avvio dell'azione. Il bridge registra sospensione, connessione, inizializzazione, upload, errore primario, ingresso nel `finally` ed errore di recupero. Nel ciclo senza file gli errori primario e di recupero hanno codici distinti.
- Il server registra ingresso e risposta dei comandi, EOF, timeout di lettura e altri errori del canale. Il servizio registra begin, restore, morte del proprietario e scadenza watchdog.
- `STATUS` legge proprietario della lease, registro pendente e generazione. Usa esclusivamente lo stream esistente. La richiesta di stato evita riconnessione, bootstrap, ripristino ed estensione del watchdog. Anche il timestamp di inattività del server viene conservato.
- `adbStatus` restituisce anche ultima fase ed esito del bridge. Nel dialogo il pulsante **Aggiorna stato diagnostico** mostra la lease attiva, inattiva, sconosciuta o il servizio scollegato. Il marker locale `pendingRestore` conserva il significato di obbligo di recupero dell'app. La lettura del registro descrive l'obbligo lato servizio.

Il protocollo musicale vive in `ZeppSession` e resta fuori dall'incremento diagnostico. Il nuovo comando appartiene al solo canale di gestione della lease.

## Verifiche locali

Verifica completata con 11 test Flutter e 47 test JVM superati, compilazione Android debug riuscita e `flutter analyze` senza segnalazioni. Gradle segnala deprecazioni nella configurazione e nei plugin esistenti.

- Il test Dart usa la stessa coda di richieste della connessione reale, estratta in `ZeppAdbRequests`. Fa scadere i 25 secondi di attesa di `BEGIN`, osserva `RESTORE` accodato e verifica che la risposta tardiva al primo ID lasci il secondo in attesa della propria risposta.
- Il test JVM blocca una revoca dentro `ZeppPermissionLease.begin`, simula la scadenza del client e accoda il ripristino su un executor singolo. Dopo il completamento verifica tutti i permessi concessi e il registro chiuso.
- Un test Flutter interroga lo stato con helper scollegato e verifica la risposta `unavailable` senza accesso a credenziali o socket.
- Questi test coprono separatamente coda Dart e transazione JVM. Il trasporto Android `LocalServerSocket`, il processo shell e il comportamento OEM richiedono il checkpoint sul telefono.

Comandi dalla directory Flutter `syncbeat` e dalla sua sottodirectory `android` rispettivamente.

```powershell
flutter test test/zepp_adb_requests_test.dart test/zepp_transfer_test.dart test/embedded_adb_test.dart --no-pub
flutter analyze --no-pub
```

```powershell
./gradlew.bat :app:testDebugUnitTest --offline --console=plain
```

## Piano di prova del checkpoint 1.4

Preparare una prova singola concordando file, azione e baseline dei permessi. Registrare orario, stato del debug wireless e funzionamento iniziale di Zepp. La riproduzione dell'invio può scrivere un brano o lasciare un file parziale sul lettore, come indicato nella conferma dell'app.

Raccogliere i tag `SyncBeatZeppDiag`, `SyncBeatZepp` e `flutter` nello stesso intervallo. Per il confronto usare `wallMs` e ID delle richieste, con `monoMs` per le durate native. Confrontare il primo errore, la successiva entrata nel `finally`, l'eventuale perdita del canale e l'inizio del ripristino. Una risposta `OK` a `BEGIN` conferma la conclusione della revoca lato servizio. Lo stato corrente effettivo dei permessi richiede una lettura indipendente durante la prova.

Al termine rileggere lo stato diagnostico e verificare i permessi Android e il funzionamento di Zepp. Documentare l'ultima fase raggiunta e l'ordine degli eventi. In caso di log insufficiente o mancata riproduzione, documentare il perimetro rimasto aperto prima di proporre una correzione della Fase 2.

## Prova in diretta completata il 19 novembre 2026

APK release diagnostico installato tramite aggiornamento ADB alle 11:18. Una prima prova dell'utente ha registrato `Broken pipe` durante il bootstrap, con fallimento complessivo dopo circa 95 secondi. Alla lettura successiva il debug wireless risultava spento. Questa lettura successiva lascia aperto il momento preciso dello spegnimento rispetto all'errore.

La prova concordata in diretta è iniziata alle 11:33:09, ora di Roma, con debug wireless riattivato dall'utente e gestione Zepp attiva. Il messaggio finale è stato letto direttamente dalla gerarchia di accessibilità del telefono su richiesta dell'utente.

> Debug wireless non disponibile. Riconnetti ADB in SyncBeat.
> Ripristino Zepp non confermato. Riconnetti il debug wireless e premi Ripristina permessi Zepp.
> Nessun reset e nessun nuovo tentativo automatico.

| Ora di Roma | Evidenza del tentativo in diretta |
| --- | --- |
| 11:33:09.568 | Avvio invio con gestione Zepp attiva. |
| 11:33:09.610 | adbd rifiuta la prima apertura del socket locale. |
| 11:33:19.614 | adbd riceve il comando di lancio del servizio. |
| 11:33:20.146 | Apertura successiva rifiutata. |
| 11:33:30.146 | Errore primario nella fase di sospensione, seguito dal `finally`. |
| 11:33:40.162 | Nuovo comando di lancio durante il recupero. |
| 11:33:40.706 | Apertura del socket di recupero rifiutata. |
| 11:33:40.819 | Compare `SERVER_START`, 113 ms dopo il rifiuto. Il costruttore del socket segue questo log. |
| 11:33:40.822 | Il recupero iniziale del servizio termina senza registro da ripristinare. |
| 11:33:50.707 | Errore del recupero e chiusura del tentativo dopo 41,138 secondi. |

Mancano `BEGIN_WRITE`, `LEASE_BEGIN_ENTER`, connessione Classic e upload nell'intero tentativo raccolto. Tutti e tre i permessi Bluetooth risultano concessi in ogni campione indipendente, raccolto circa una volta al secondo per tre minuti. La lettura finale conferma gli stessi flag e l'assenza del registro di ripristino e del backup. Rimane soltanto `lease.lock`. Il socket del servizio risulta presente dopo l'errore.

Il blocco osservato è nel collegamento al servizio locale, prima della revoca. Nel percorso di recupero la connessione precede l'avvio del servizio, dimostrando che l'attesa fissa di 500 ms in `_ensureHelper` può scadere prima che il listener esista. La ragione per cui il primo lancio della prova in diretta manca di `SERVER_START` resta aperta. Il difetto inizialmente riferito come ripristino prematuro durante un invio resta da rivalutare dopo aver risolto questo blocco preliminare.

Il checkpoint ha ristretto il perimetro al bootstrap e all'apertura dello stream. L'incremento successivo da progettare riguarda un segnale esplicito di prontezza del servizio e la distinzione tra rifiuto immediato dello stream e timeout. I log del pacchetto locale `flutter_adb` e la sua implementazione mostrano che `open()` attende fino a 10 secondi anche quando il peer ha già chiuso lo stream.

Gli artefatti locali della prova sono nella cartella ignorata da Git `tools/zepp-transfer/phase1-live/`. La raccolta log è stata chiusa e il campionamento dei permessi è terminato. Il codice applicativo resta quello della build diagnostica installata.
