# Bootstrap con READY, resoconto del 19 novembre 2026

L'incremento è stato implementato, installato e verificato sullo Xiaomi. La correzione del comando di lancio installata alle 14:47:41 ha superato entrambi i checkpoint dal percorso dell'app. Su successiva richiesta dell'utente è riuscito anche un singolo invio MP3, completato in 84,494 secondi. L'utente ha confermato riproduzione del brano e funzionamento di Zepp. Permessi e flag finali coincidono con la baseline. La cronologia delle versioni precedenti e i limiti delle prove sono riportati di seguito.

## Modifica eseguita

- La preparazione riusa uno stream helper valido oppure lancia una volta il servizio su un endpoint nuovo per il gesto. Le chiamate concorrenti condividono la stessa preparazione.
- Il servizio emette `SYNCBEAT_READY_V1` dopo la costruzione del socket e il recupero iniziale verificato. Lo stdout viene chiuso dopo il segnale, mentre il servizio conserva socket e meccanismi di recupero.
- Dart attende quella riga sullo stream shell prima dell'unica apertura del socket. La pausa fissa di 500 ms e l'apertura preventiva del socket sono state rimosse.
- La gestione locale degli stream ADB installa gli osservatori prima di `OPEN` e conserva i payload precoci. Distingue rifiuto prima di `OKAY`, timeout, perdita del trasporto, EOF prima di `READY` e segnale non valido. La dipendenza resta fissata a `flutter_adb` 1.0.0.
- I codici attraversano il coordinatore nativo e il dialogo. Il recupero dal `finally` usa il canale disponibile e conserva lo stato pendente in caso di errore. La facoltà di avviare il servizio appartiene alla preparazione esplicita o al pulsante manuale di ripristino, eliminando il secondo bootstrap automatico.
- È stato aggiunto il pulsante **Prepara servizio ADB (senza sospensione)** nel dialogo esistente per eseguire il primo checkpoint attraverso l'app.

Le scelte operative introdotte sono l'endpoint nuovo per preparazione e l'uso dello stdout shell come canale del segnale, già proposti nel progetto. Il protocollo musicale e la struttura generale dell'app restano fuori dall'incremento.

## Verifiche locali completate

Sono passati 18 test Flutter pertinenti e tutti i 47 test JVM. `flutter analyze --no-pub` è terminato senza segnalazioni. Sono riuscite la compilazione Android e la build APK release finale. Gradle continua a segnalare deprecazioni dei plugin esistenti.

I test nuovi coprono il segnale immediato conservato prima della sottoscrizione, il segnale spezzato e ritardato oltre 500 ms, la distinzione tra rifiuto e silenzio del peer, la perdita del trasporto, EOF e timeout prima di `READY`, la risposta tardiva, la preparazione concorrente e il recupero dopo bootstrap fallito con contatori dei lanci invariati.

I limiti locali restano 5 secondi per `READY` e 10 secondi per ciascuna apertura. I test controllano la classificazione e la scadenza di questi limiti. La loro adeguatezza sul telefono richiede una preparazione riuscita e ulteriori osservazioni.

## Installazione e primo checkpoint della versione iniziale

APK release installato come aggiornamento alle **14:23:21, ora di Roma**, con `adb install -r` concluso con `Success`. Il telefono è `VSN7KNLZB689KBEE`, Xiaomi 15T. Il debug wireless è stato riattivato dall'utente. La baseline esterna mostrava i tre permessi Bluetooth di Zepp concessi e soltanto `lease.lock` nella directory del registro.

I comandi touch e tastiera ADB non hanno aperto i controlli dell'app, pur terminando senza un errore esplicito. L'utente ha quindi eseguito la navigazione e premuto il pulsante di preparazione. L'agente ha registrato i log e controllato lo stato finale direttamente via ADB.

| Ora di Roma | Evento osservato |
| --- | --- |
| 14:26:27.404 | Il bridge riceve `prepareZeppHelper`. |
| 14:26:27.405 | Dart entra in `HELPER_ENSURE`, tentativo 1. |
| 14:26:27.406 | Un solo evento `HELPER_LAUNCH`. |
| 14:26:27.412 | adbd riceve lo stream shell di lancio. |
| 14:26:27.459 | Lo stream termina prima del segnale. Dart registra `HELPER_LAUNCH_CLOSED` e `ADB_BOOTSTRAP_EXITED`. |
| 14:26:27.461 | L'azione termina con errore dopo 57 ms. |

Il codice dell'esito corrisponde al messaggio **Il lancio ADB è terminato prima del segnale READY.** L'errore comunicato dall'utente come collegamento ADB è localizzato dai log nella preparazione del servizio, successiva alla connessione ADB.

La registrazione contiene un lancio e zero eventi `SERVER_START`, `SERVER_READY`, `HELPER_READY`, `HELPER_SOCKET_OPEN` e `BEGIN_WRITE`. La lettura successiva di `/proc/net/unix` trova zero socket helper. Tutti e tre i permessi Zepp e i flag risultano ancora coincidenti con la baseline. La directory del registro contiene ancora soltanto `lease.lock`.

Il vincolo di attendere il segnale ha fermato la sequenza prima del socket. Il trasporto di `READY` attraverso questa modalità di shell, e la sopravvivenza del servizio dopo la chiusura del canale, restano da dimostrare. L'EOF a 57 ms precede entrambe le scadenze configurate e lascia aperta la validazione hardware dei limiti di 5 e 10 secondi.

Questo esito lascia aperta la causa della terminazione anticipata del lancio. Il comando redirige stderr su `/dev/null`, quindi il tentativo non conserva l'eventuale errore di avvio emesso su quel canale. Il meccanismo di avvio e il suo segnale richiedono una nuova diagnosi circoscritta prima del secondo checkpoint.

## Esito della versione iniziale

Il primo checkpoint è fallito. L'avanzamento è fermo a questo esito, secondo l'istruzione dell'utente. Restano pendenti il ciclo senza file, la dimostrazione della durata adeguata dei limiti su hardware e la rivalutazione del difetto iniziale sul flusso di invio.

La raccolta locale è in `tools/zepp-transfer/bootstrap-ready/`, esclusa da Git. La build installata contiene l'incremento descritto. La modifica è una preparazione implementata e verificata localmente, con validazione hardware ancora aperta.

## Correzione successiva del lancio

Su richiesta dell'utente è proseguito il lavoro sul bootstrap. Il comando iniziale lasciava terminare subito la shell che avviava il processo in background. È stato aggiunto `wait` per mantenere aperto il canale fino al segnale. Una prima prova diretta da CLI ha ricevuto `READY` in 321 ms, con socket persistente dopo la chiusura del collegamento. La build installata alle 14:34:54 ha tuttavia prodotto ancora `ADB_BOOTSTRAP_EXITED` dall'app, dopo 48 ms alle 14:41:03.

Il confronto successivo ha rilevato la differenza di ambiente. Sul telefono `shell:`, `shell,raw:` ed `exec:` esponevano stdout attraverso `/dev/pts/0`. La CLI usava il protocollo shell v2, con stdout su socket. L'implementazione AOSP documenta la conversione dei sottoprocessi senza protocollo shell in PTY per gestirne la chiusura. [AOSP, gestione dei sottoprocessi ADB](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/shell_service.cpp)

La prima prova da CLI validava quindi il canale shell v2. Per riprodurre il percorso dell'app è stata usata direttamente la richiesta legacy `shell:` attraverso il server ADB, mantenendo UID e APK installato del servizio.

Il comando corrente esegue `trap "" HUP` nel sottoprocesso che diventa il servizio mediante `exec`, con stdin e stderr su `/dev/null`. La shell padre resta in `wait` fino alla chiusura del canale da parte del client, successiva a `READY`. Questo conserva l'ignoramento del segnale di disconnessione senza affidare a `nohup` la gestione di stdout sul terminale virtuale.

La prova diretta della richiesta legacy ha prodotto i seguenti risultati.

- Ricezione della riga `SYNCBEAT_READY_V1` in **447 ms**.
- Socket del servizio ancora presente dopo la chiusura del collegamento shell.
- Un solo processo avviato per questa prova, senza richieste di `BEGIN`.

La correzione è stata compilata e installata alle **14:47:41, ora di Roma**. Sono passati nuovamente i 18 test Flutter pertinenti, i 47 test JVM e l'analisi statica. Il comando mantiene un lancio e un'apertura del socket per gesto, con attesa del segnale e recupero senza bootstrap aggiuntivo.

## Predisposizione della verifica dal percorso dell'app

La prova diretta del servizio conferma l'arrivo del segnale sulla modalità legacy e la permanenza del listener dopo la chiusura. La verifica attraverso `EmbeddedAdb` e il pulsante di preparazione resta necessaria per chiudere il primo checkpoint. Il secondo checkpoint usa soltanto il ciclo di sospensione e ripristino senza file.

Durante la predisposizione della verifica la finestra attiva risultava `com.android.systemui` e lo stato del keyguard riportava `showing=true`. La revisione automatica ha bloccato `wm dismiss-keyguard` perché interviene sulla schermata di sicurezza. È stato richiesto all'utente lo sblocco manuale.

È stato preparato un test UI temporaneo da eseguire tramite il runner di sistema, senza installare app aggiuntive. La sua operatività riguarda esclusivamente i controlli dei checkpoint nell'app SyncBeat. Il primo controllo ha letto la finestra di sistema mentre il telefono era bloccato. Nessuna azione sui permessi è stata avviata da quel test.

La registrazione successiva è in `tools/zepp-transfer/bootstrap-ready-wait/`. I checkpoint successivi sono riportati di seguito.

## Checkpoint riusciti dall'app

Dopo lo sblocco manuale i comandi touch e le azioni di accessibilità hanno continuato a terminare senza aprire i controlli richiesti. L'utente ha quindi eseguito i gesti nell'app. L'agente ha registrato i log, osservato i permessi e verificato lo stato finale direttamente via ADB.

| Checkpoint | Evidenza dal telefono | Esito |
| --- | --- | --- |
| Preparazione senza revoca, 15:12:31 | Un lancio alle 15:12:31.346, `SERVER_READY` alle .614, `HELPER_READY` e chiusura del canale shell alle .616, socket collegato alle .624 e risposta a `PING` alle .627. | Successo in 284 ms. Zero comandi `BEGIN`. Permessi concessi. |
| Sospensione e ripristino senza file, 15:13:27 | Un lancio alle 15:13:27.586, `READY` ricevuto alle .847, socket collegato alle .851. `BEGIN` confermato alle 15:13:28.848 e `RESTORE` confermato alle 15:13:29.864. | Successo in 2.292 ms. Permessi e flag finali identici alla baseline, registro assente. |

I processi dei due servizi, PID 13239 e 13707, erano ancora vivi alla verifica successiva alla chiusura dei rispettivi canali shell. Il secondo gesto ha preparato un nuovo endpoint dopo la chiusura del client inattivo del primo servizio, avvenuta circa 15 secondi dopo la lettura di stato. Ciascun gesto ha prodotto un solo lancio e una sola apertura del socket. Il recupero del secondo checkpoint ha usato lo stesso canale del proprio `BEGIN`.

Il campionamento indipendente ha registrato permessi negati durante le transizioni e il ritorno ai tre permessi concessi. Il confronto finale ha verificato anche l'uguaglianza esatta dei flag. Il campionamento è timestampato sul PC, mentre `wallMs` nei log proviene dal telefono. Una misura di riconciliazione ha rilevato il PC avanti di 2,568 secondi, con incertezza di circa 24 ms. Le tabelle usano l'ora del telefono convertita a Roma.

I limiti configurati di 5 e 10 secondi hanno consentito questi avvii riusciti. La verifica copre le condizioni osservate e conserva quei valori come configurazioni.

## Singolo invio MP3 richiesto dall'utente

Dopo il superamento dei checkpoint l'utente ha chiesto di provare anche l'invio. È stato osservato un solo gesto di invio, con gestione Zepp attiva e raccolta dei log. La successiva conferma dell'utente riguarda sia la riproduzione sul lettore originale sia il ritorno al funzionamento di Zepp.

| Ora di Roma | Evento osservato |
| --- | --- |
| 15:17:12.203 | Avvio dell'invio con gestione Zepp attiva. |
| 15:17:12.244 | Un solo lancio del servizio per questo gesto. |
| 15:17:12.476 | Ricezione di `READY` e chiusura del canale shell. |
| 15:17:12.481 | Collegamento al socket e scrittura di `BEGIN`. |
| 15:17:13.477 | Conferma di `BEGIN`. |
| 15:17:13.978 | Avvio connessione Classic. |
| 15:17:31.069 | Classic collegato dopo 17.090 ms. |
| 15:17:32.956 | Autenticazione completata e inizio upload. |
| 15:18:35.642 | Ultimo blocco confermato dall'orologio, seguito da `RUN_FINALLY completed=true primaryFailed=false`. |
| 15:18:35.646 | Scrittura di `RESTORE`, successiva all'ultimo ACK. |
| 15:18:36.678 | Ripristino verificato dal servizio. |
| 15:18:36.697 | Invio concluso con successo dopo 84.494 ms. |

Il campionamento indipendente durante il trasferimento mostra tutti e tre i permessi Zepp negati. Il servizio risponde ai `PING` durante l'upload. Il confronto finale con la baseline del test MP3 conferma tre permessi concessi e flag coincidenti. La directory del registro contiene soltanto `lease.lock`.

La lettura diretta del dialogo ha restituito **Ultimo blocco confermato dall'orologio** e il messaggio di ripristino allo stato iniziale. L'utente ha successivamente confermato **Il brano si riproduce e Zepp funziona**.

La prova attuale dimostra l'ordinamento corretto di questo singolo invio, con sospensione mantenuta durante l'upload e ripristino dopo l'ACK finale. La ricostruzione completa del guasto riferito prima della strumentazione resta indeterminata. La correzione implementata riguarda il bootstrap e il suo canale di prontezza.

## Modifiche apportate, 20 novembre 2026

Progetto SyncBeat. Primo incremento del piano `syncbeat-piano-codex-invio-download-e-senza-wifi-2d2bc3a9.md.txt`, con priorità alla mobilità e al checkpoint B1. Questa sezione aggiunge il lavoro del 20 novembre alla cronologia precedente.

- **Punto 3, baseline e branch.** Workspace iniziale pulito, stash vuoto. Il fetch ha aggiornato `origin/main` a `fff2a65d0830a0ecc19ba9d45cadc08b59df9d76`, con albero coincidente con `00e869aca511f5480f14fb48273afb51c253f381`. È stato creato `feature/helper-senza-wifi` da quella baseline. L'invio del 19 novembre e la conferma dell'utente restano evidenze valide.
- **Punti 5.1 e 5.5/B1, canale diretto.** Il client è in Dart, in `zepp_direct_status.dart`. Il listener di solo stato è in `ZeppDirectStatusServer.kt`, avviato mediante una modalità distinta dell'entrypoint shell già esistente. Questa modalità precede la costruzione del servizio dei permessi ed espone soltanto `STATUS`. Il server rifiuta gli altri comandi. Il dialogo esistente offre due pulsanti per preparazione e lettura dello stato.
- **Punto 5.1, scelta dell'IPC.** È stato scelto TCP IPv4 su `127.0.0.1`, con porta effimera assegnata dal kernel. Il trasporto diretto e l'orchestrazione restano in Dart, usando `Socket` e la coda di richieste esistente. Il codice nativo si limita al listener nel processo shell e al controllo dei messaggi. Una variante Binder richiederebbe anche la distribuzione del binder tra i processi. Una variante Unix richiederebbe un adattatore specifico della piattaforma per indirizzamento e credenziali del peer. La scelta TCP richiede la prova reale B1 su Android e HyperOS.
- **Punto 5.2, autenticazione.** Ogni preparazione genera in Dart un segreto indipendente da 32 byte con `Random.secure`. Il comando shell contiene soltanto modalità e percorso APK. Dopo `stty -echo`, il processo emette un marcatore fisso di input. Soltanto allora l'app invia la credenziale su stdin del bootstrap ADB autenticato. La risposta di prontezza comunica la porta locale, senza includere credenziali. La connessione locale presenta la credenziale, confrontata con `MessageDigest.isEqual`. Dopo il successo il listener chiude l'accesso a nuove connessioni e il buffer della credenziale attesa viene azzerato.
- **Punto 5.2, identità del client.** La scelta TCP autentica il possesso della credenziale privata del bootstrap. Il controllo OS dell'UID del peer tramite `SO_PEERCRED` appartiene ai socket Unix e qui non è disponibile. Il listener verifica comunque l'indirizzo loopback e l'entrypoint controlla il proprio UID shell/root. Le richieste senza credenziale, con credenziale errata e con una credenziale di un'altra sessione vengono rifiutate nei test. I log riportano codici fissi, ID numerici e PID, con i payload esclusi.
- **Punto 5.3, ciclo di vita.** La sessione vive nella RAM del processo SyncBeat e dell'helper. Dopo l'autenticazione il server attende sul collegamento già aperto, senza richiedere heartbeat o riconnessioni. EOF termina il processo di prova. Morte dell'app, morte dell'helper e riavvio richiedono un nuovo bootstrap con Wi-Fi. La sopravvivenza con schermo spento su HyperOS resta da verificare.
- **Punti 5.4 e 5.5, perimetro di sicurezza.** Il canale B1 non contiene chiamate al servizio dei permessi. `BEGIN`, `RESTORE` e altri comandi ricevono `ERR`, anche dopo autenticazione. Prima dell'estensione B2 restano richiesti progetto e simulazione del recupero con helper morto, rilevamento del caso all'avvio dell'app e istruzioni di ripristino manuale. Le prove di guasto con permessi sospesi richiedono il percorso di recupero previsto dal piano.
- **Punti 4 e 4b, workstream indipendenti.** Il pulsante nel popup di download e la discovery NSD della porta ADB appartengono ai rispettivi incrementi A e A2. B1 usa l'ADB già autorizzato oppure la porta salvata con un singolo tentativo. Un errore richiede una nuova azione esplicita. La porta locale del nuovo canale viene invece acquisita automaticamente dal bootstrap.

### Verifiche locali B1

Sono passati 24 test Flutter pertinenti e 51 test JVM, con `flutter analyze --no-pub` senza segnalazioni. La build release Android è riuscita: APK locale in `build/app/outputs/flutter-apk/app-release.apk` (177,1 MB), non installato sul telefono. I test includono il percorso normale `prepareOfflineStatus` e successive letture con connessione ADB simulata come persa, mantenendo un solo bootstrap e una sola connessione diretta. La credenziale viene controllata come presente soltanto nello stdin del bootstrap. Un test widget verifica i due pulsanti senza operazioni sui permessi, chiamate di invio o refresh ADB impliciti.

I test JVM usano socket loopback reali sul PC e verificano autenticazione obbligatoria, credenziale errata, credenziale di una sessione diversa, chiusura del listener dopo autenticazione, rifiuto dei comandi di modifica, limite dei frame e fine della sessione dopo EOF. Le letture di frame e le risposte sono limitate a 5 secondi, come il limite di bootstrap già usato. Il server attende fino a 15 secondi per l'autenticazione iniziale, poi ammette inattività sulla connessione autenticata. I limiti di 5 e 15 secondi sono configurazioni dell'incremento da valutare nella prova reale.

### Checkpoint B1 sul telefono da concordare

La prova proposta richiede l'accordo specifico previsto nei punti 3.5 e 5.5 del piano.

1. Collegare e sbloccare il telefono, con Wi-Fi attivo e ADB autorizzato. Rilevare stato e flag dei tre permessi Zepp e verificare l'assenza di un ciclo di ripristino pendente.
2. Installare l'APK aggiornato. Dal dialogo esistente premere **Prepara canale senza Wi-Fi (solo stato)** una volta. Registrare il bootstrap, la sua chiusura, l'autenticazione e `DIRECT_STATUS_OK` con PID del servizio.
3. Spegnere temporaneamente il Wi-Fi lasciando l'app in primo piano. Premere una volta **Verifica canale locale (solo stato)**. Verificare la risposta dello stesso PID e i contatori del bootstrap invariati.
4. Confrontare nuovamente permessi e flag con la baseline, poi riattivare il Wi-Fi. Riportare separatamente l'esito B1 e fermare l'avanzamento a quel checkpoint.

La prova reale B1 resta pendente. Il passaggio a B2 segue il superamento di B1 e la preparazione del recupero del punto 5.4. Il modello concettuale di avvio privilegiato tramite ADB e i limiti di riavvio sono descritti anche nella [guida ufficiale Shizuku](https://shizuku.rikka.app/guide/setup/).
