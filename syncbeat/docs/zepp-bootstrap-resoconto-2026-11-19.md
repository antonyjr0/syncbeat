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

## Modifiche apportate, 23 novembre 2026: verifica B1 sul telefono

Progetto SyncBeat, punti 3.5 e 5.5/B1 del piano. L'utente ha richiesto l'installazione dell'aggiornamento per provarlo e ha eseguito i gesti dall'app. L'APK release del commit `28a2bd7` è stato installato via USB con `adb install -r`, esito `Success`, conservando i dati. Questa verifica aggiorna lo stato pendente riportato nella sezione del 20 novembre.

**Esito B1: superato nelle condizioni osservate.** Il bootstrap ha consegnato il marcatore di input, poi `READY`; la shell è stata chiusa prima dell'autenticazione e delle letture dal canale diretto. I log mostrano un solo `DIRECT_BOOTSTRAP_START` e un solo `AUTH_WRITE`. Il servizio è rimasto lo stesso processo shell, UID 2000 e PID 23107.

| Ora nel logcat del telefono | Evento |
| --- | --- |
| 11:35:53.936 | Avvio del bootstrap diretto. |
| 11:35:54.238 | Conferma del canale di input. |
| 11:35:54.242 | Ricezione di `READY` e chiusura del bootstrap. |
| 11:35:54.249 | Autenticazione locale confermata. |
| 11:35:54.250 | Prima risposta di stato, PID 23107. |
| 11:36:01.443 | Perdita del precedente helper su ADB (`HELPER_LOST`). |
| 11:36:04.370 | Ulteriore risposta dal canale diretto, stesso PID. |
| 11:37:18.627, 11:37:23.589, 11:37:28.916 | Risposte di stato dallo stesso PID, senza nuovo bootstrap o nuova autenticazione. |

La lettura indipendente via USB ha rilevato `wifi_on=0` e `adb_wifi_enabled=0` prima delle ultime due risposte e nuovamente al termine. Non è stato campionato l'istante esatto dello spegnimento. L'USB è servito alla raccolta dei log; le richieste di stato dell'app usano il collegamento locale Dart già autenticato. Non è stato letto il testo finale del dialogo tramite UI Automator; la conferma dell'esito deriva dalle risposte diagnostiche validate dall'app e dal PID del processo rilevato via USB.

I tre permessi Zepp `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` e `BLUETOOTH_ADVERTISE` risultano concessi, con flag identici alla baseline salvata prima della prova. Nessun `BEGIN_WRITE` o `RESTORE_WRITE` nei log raccolti. La directory del registro contiene soltanto `lease.lock`. L'utente ha eseguito anche la preparazione del precedente helper ADB, che nei log compie soltanto `PING` e `STATUS`.

La prova valida il canale diretto in primo piano e la sua sopravvivenza alla chiusura della shell e alla perdita del Wi-Fi/Debug wireless. I tempi osservati rientrano nei limiti configurati, senza dimostrarne la validità in ogni condizione. Restano da verificare schermo spento/HyperOS e il recupero del punto 5.4. B2 e B3 non sono stati eseguiti; nessun invio MP3 in questa prova. Il checkpoint si ferma qui. Evidenze locali, escluse da Git, in `tools/zepp-transfer/b1-local-channel/`.

## Modifiche apportate, 23 novembre 2026: invio dai download

Progetto SyncBeat, incremento A, punto 4 del piano. Dopo B1 l’utente ha chiesto di implementare l’invio senza Wi-Fi, dando però precedenza all’invio dalla schermata di download. Ha poi precisato che il flusso normale deve gestire automaticamente i passaggi dopo il download, senza aprire il dialogo operativo o usare pulsanti diagnostici. Questa richiesta aggiorna il precedente requisito del piano che escludeva l’invio automatico dopo il salvataggio.

- **Punto 4, popup di download.** `audio_match_dialog.dart` e `youtube_match_dialog.dart` avviano l’invio su Android dopo un salvataggio riuscito. Usano percorso e nome effettivamente restituiti da `StagedAudioFile`, senza ricostruire un percorso. L’avanzamento e l’esito restano nel popup già aperto. Windows conserva il comportamento di download precedente.
- **Punto 4, orchestrazione in Dart.** `ZeppDownloadTransfer` seleziona soltanto un dispositivo abbinato con chiave valida salvata. Se è stata memorizzata una preferenza, non sceglie un altro dispositivo quando quello manca. Senza preferenza e con più candidati configurati richiede una scelta. Riusa `ZeppClient.send` e il coordinamento esistente, senza cambiare protocollo musicale, trasporto Bluetooth o codice nativo.
- **Punto 4, configurazione iniziale.** Il dialogo esistente ha una modalità limitata a scelta dell’orologio, chiave e autorizzazione del coordinamento. Non mostra comandi diagnostici e non esegue cicli sui permessi né trasferimenti. La chiave e la preferenza restano nell’archivio sicuro. Dopo **Salva e continua**, il download già salvato prosegue con un solo invio effettivo.
- **Punti 3.4 e 4, errori e annullamento.** Un tentativo di invio per download, nessuna coda o retry automatico. Un errore conserva il file e abilita un nuovo invio esplicito dal popup, senza un altro download. Non viene mantenuta un’azione riferita al vecchio risultato dopo un nuovo download fallito o una selezione cambiata. L’annullamento durante la preparazione impedisce il successivo avvio del trasferimento; durante un trasferimento attivo richiama la cancellazione nativa e il suo `finally` di ripristino. Il controllo di un ripristino pendente blocca l’invio prima della sospensione.
- **Punti 4b, 5.4 e 5.5, limiti.** L’incremento A continua a usare il canale ADB esistente per i permessi. Discovery della porta e invio sul canale diretto offline appartengono ai passi successivi. Il messaggio conservativo in presenza di un ripristino pendente non costituisce la validazione completa del recupero con helper morto richiesta dal punto 5.4. B2 e B3 restano da implementare e provare separatamente.

### Verifiche dell’incremento A

Suite Flutter completa: **178 test superati**. L’analisi statica è senza segnalazioni. I test pertinenti coprono invio automatico con il vero URI/percorso restituito dal salvataggio, mantenimento del file dopo errore, nuovo invio esplicito senza riscaricare, assenza di retry/coda, scelta univoca del destinatario, preferenza memorizzata, blocco con ripristino pendente e annullamento durante preparazione e invio. I test widget verificano anche la configurazione iniziale senza operazioni sui permessi o musica e le regressioni del percorso manuale. I test usano client simulati: il nuovo percorso automatico dai download non è ancora verificato sul telefono. La prova A richiede un download e il successivo invio automatico con Wi-Fi, mantenendo il confronto dei permessi prima/dopo. Nessuna prova MP3 offline in questo incremento.

La verifica finale dei file interessati ha superato **26 test pertinenti**, incluse le impaginazioni su schermo stretto dopo l’aggiornamento dei testi. L’APK release finale è stato compilato e installato via USB con `adb install -r`, esito `Success`, in continuità con la richiesta dell’utente di installare gli aggiornamenti in questa sessione. L’app è stata aperta, senza avviare download o invii. Prima dell’installazione i tre permessi Zepp erano concessi e il registro conteneva soltanto `lease.lock`. Il nuovo percorso automatico resta da verificare con un download eseguito dall’utente; l’avanzamento al canale offline segue questo primo checkpoint.

## Modifiche apportate, 23 novembre 2026: correzione dell’invio e incremento A2

Progetto SyncBeat, punti 4 e 4b del piano. L’utente ha chiarito che l’invio deve essere esplicito: l’automatismo richiesto riguarda porta, connessione e preparazione del servizio all’apertura dell’app. L’autoinvio del commit `59b46e4`, descritto nella sezione precedente, derivava da un’interpretazione errata ed è superato da questa correzione.

- **Punto 4, gesto di invio.** Il solo download non chiama più il coordinatore di invio. Il pulsante **Invia all’orologio** compare dopo il salvataggio e usa il file effettivamente restituito. La configurazione già memorizzata viene riusata; l’avanzamento rimane nel popup. I test widget richiedono zero invii dopo il download e un invio soltanto dopo il tap.
- **Punto 4b, discovery e collegamento.** Il sottile adattatore Kotlin `AdbConnectDiscovery` osserva NSD e risolve in sequenza soltanto `_adb-tls-connect._tcp`. Restituisce metadati e indirizzi locali a Dart, senza connettersi. `adb_connect_discovery.dart` esclude pairing, servizi legacy, indirizzi di altri dispositivi, loopback pubblicizzati e porte non valide. Seleziona un solo candidato locale non ambiguo. `EmbeddedAdb` apre una sola connessione TLS a `127.0.0.1` sulla porta scoperta, senza provare poi quella salvata. Richieste contemporanee condividono il tentativo.
- **Punto 4b, momento della preparazione.** `main.dart` attiva la preparazione dopo l’avvio dell’interfaccia. Una riapertura reale dopo la pausa dell’app può eseguire un nuovo tentativo, mentre notifiche di focus e osservazioni non creano un ciclo di retry. Un collegamento già pronto viene riusato. La home mostra un messaggio di stato e un accesso alla configurazione se necessario. All’apertura viene preparato soltanto il canale autenticato B1 di stato: nessun `BEGIN`, `RESTORE` o invio musicale.
- **Punti 3.4 e 4b, configurazione e limiti.** Dopo il pairing dalla notifica, la porta di connessione viene cercata automaticamente. Il campo manuale è un recupero mostrato dopo un errore. Attivazione e autorizzazioni Android restano richieste; non si promette che il Debug wireless rimanga abilitato dopo ogni riavvio o cambio rete. Il filtro del candidato e l’orchestrazione restano in Dart; il nuovo codice nativo riguarda soltanto l’API NSD.
- **Punti 5.4 e 5.5, perimetro.** Questo lavoro non abilita comandi sui permessi nel canale diretto né l’invio MP3 offline. La preparazione automatica non sostituisce la validazione del recupero con helper morto e dei checkpoint B2/B3.

Verifiche locali: **187 test Flutter superati**, **51 test JVM superati**, analisi statica senza segnalazioni. I test aggiunti coprono esclusione di dispositivi remoti e pairing, deduplicazione IPv4/IPv6, ambiguità e input non validi, un solo tentativo TLS anche in caso di rifiuto, nessun secondo tentativo sulla porta salvata, preparazione condivisa e assenza di retry dopo errore finché non avviene una nuova apertura esplicita. La selezione normalizza anche tipi NSD con punto iniziale/finale, suffisso `.local` e maiuscole DNS; il servizio di pairing resta escluso.

Riferimenti primari per la scelta: [Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd) e [architettura ADB Wi-Fi di AOSP](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md). La finestra di discovery nativa è 5 secondi, con scadenza complessiva di 10 secondi e limite Dart di 12 secondi. Sono configurazioni, non garanzie universali di risposta.

### Prima prova di apertura A2

L’utente ha attivato Wi-Fi e Debug wireless e ha concordato la verifica della sola preparazione. La prima build corretta, con invio soltanto su tap, è stata installata e aperta via USB. Il processo app PID 9910 ha registrato `ADB_DISCOVERY_START` alle 15:34:42.760 del logcat e `ADB_AUTO_CONNECT_ERROR` / `APP_PREPARATION_ERROR` alle 15:34:47.906–907. Non compare `ADB_DISCOVERY_SELECTED`: la prova si è fermata prima di un tentativo di connessione. I tre permessi Zepp risultano ancora concessi con gli stessi flag e il registro contiene soltanto `lease.lock`.

La prima diagnostica non esponeva il motivo specifico della mancata selezione. È stata aggiunta la normalizzazione dei tipi NSD e una diagnostica limitata a codici fissi e contatori di servizi, indirizzi locali e candidati, senza nomi servizio o identificatori. La causa iniziale non è quindi considerata dimostrata dalla sola prima traccia; la verifica della build aggiornata deve stabilire l’esito reale.

La build release aggiornata è compilata in `build/app/outputs/flutter-apk/app-release.apk`. Il collegamento USB si è interrotto prima della sua installazione; l’utente è stato avvisato ed è stato richiesto di ricollegare il telefono. L’ultima versione installata ha già l’invio esplicito e la prima implementazione della preparazione all’apertura, ma non l’ultima normalizzazione/diagnostica NSD. Nessun esito positivo A2 viene dichiarato finché la prova della build aggiornata non è conclusa.

## Modifiche apportate, 24 novembre 2026: verifica della preparazione automatica A2

Progetto SyncBeat, punti 4b e 5.5/B1. L’utente ha richiesto installazione e verifica con Wi-Fi e Debug wireless già attivi, specificando che porta e dati di connessione devono essere acquisiti dall’app. È stata installata via USB la release del commit `f0f4236`, esito `Success`, e avviata SyncBeat senza alcun inserimento di porta o tap sui comandi di preparazione.

**Esito: preparazione automatica riuscita sul telefono HyperOS.** NSD ha risolto due servizi e rilevato sei indirizzi locali. Il filtro Dart ha individuato un solo candidato valido per questo telefono. È seguita una sola connessione TLS, un solo bootstrap del canale diretto, una sola autenticazione e una risposta di stato del processo shell PID 27993, UID 2000.

| Ora nel logcat del telefono | Evento |
| --- | --- |
| 12:40:34.862 | Avvio della ricerca automatica. |
| 12:40:40.135 | Snapshot NSD: due servizi risolti. |
| 12:40:40.138 | Un solo candidato locale valido. |
| 12:40:40.221 | Collegamento ADB autenticato. |
| 12:40:40.222 | Avvio del bootstrap diretto. |
| 12:40:40.711 | `READY` ricevuto e chiusura del bootstrap. |
| 12:40:40.717 | Autenticazione locale confermata. |
| 12:40:40.718 | `DIRECT_STATUS_OK` e `APP_PREPARATION_READY`. |

Dal primo evento al servizio pronto sono trascorsi 5.856 ms. I log contengono una ricerca e una autenticazione, nessun `BEGIN_WRITE` e nessun `RESTORE_WRITE`. I tre permessi Zepp e i relativi flag coincidono con la baseline; il registro contiene soltanto `lease.lock`. Le evidenze locali sono in `tools/zepp-transfer/auto-open/`, escluse da Git. La prova dimostra scoperta e preparazione, non un invio musicale completo né l’accensione automatica del Debug wireless spento.
