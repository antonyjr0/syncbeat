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

## Modifiche apportate, 24 novembre 2026: predisposizione dell’accensione dall’app

Progetto SyncBeat, estensione richiesta dall’utente al punto 4b: attivare il Debug wireless direttamente dentro SyncBeat quando è collegata al Wi-Fi. L’attivazione richiede un privilegio diverso dal semplice pairing ADB. Il codice AOSP osserva l’impostazione `ADB_WIFI_ENABLED` per avviare/arrestare il trasporto, mentre `WRITE_SECURE_SETTINGS` è un permesso protetto, con flag di sviluppo, più ampio della sola impostazione interessata. Fonti: [avvio di adbd](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/how_adbd_starts.md) e [definizione dei permessi Android](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml).

- **Punto 4b, adattatore nativo minimo.** `WirelessDebugPreparation` controlla Wi-Fi e autorizzazione prima di ogni accesso alle impostazioni protette. Senza Wi-Fi non esegue letture o scritture; senza privilegio restituisce `authorization_required`. Con privilegio, il ponte Android legge soltanto `adb_wifi_enabled` e, se necessario, lo imposta a `1` una sola volta. Non espone nomi di impostazioni o valori arbitrari nel canale.
- **Punto 4b, orchestrazione Dart.** Il controllo precede la discovery. `enable_requested` è una richiesta, non un esito di connessione: resta obbligatoria la selezione di un candidato locale univoco, seguita da TLS, bootstrap e autenticazione del canale. Senza privilegio si conserva il flusso già verificato con Debug wireless attivo. Nessuna concessione del privilegio viene eseguita dal codice dell’app.
- **Punti 3.5 e 5.5, confine della prova.** La concessione una tantum di `WRITE_SECURE_SETTINGS` e la prova spento→acceso richiedono un accordo specifico, perché ampliano i poteri dell’app e modificano un’impostazione protetta. Non sono parte della precedente verifica di sola preparazione e non sono ancora state eseguite. La prova proposta prevede concessione, spegnimento temporaneo del solo Debug wireless mantenendo Wi-Fi e USB, apertura dell’app, lettura dell’effettivo ritorno a `1` e della connessione pronta, con confronto dei permessi Zepp invariati.

Verifiche locali: **191 test Flutter e 56 test JVM superati**. I nuovi test verificano i blocchi in assenza di Wi-Fi o privilegio, nessuna scrittura su servizio già abilitato, una sola richiesta di attivazione, errore senza retry su scrittura rifiutata e prosecuzione con un solo tentativo di discovery/connessione. La verifica effettiva dell’accensione su HyperOS resta pendente.

L’analisi statica è pulita e l’APK release è stato compilato e installato. Il privilegio speciale non è stato concesso. L’apertura della nuova build ha registrato `ADB_WIFI_MANUAL_ACTIVATION` alle 12:49:24.266 e `APP_PREPARATION_READY` alle 12:49:29.760, con una sola selezione locale e un solo bootstrap. Questo conferma il funzionamento senza autorizzazione aggiuntiva quando il Debug wireless è già attivo, e il mancato avvio della scrittura protetta. I permessi Zepp sono rimasti invariati. È stato richiesto l’accordo specifico per la concessione e per la prova spento→acceso dall’app; l’esito di quella prova non è ancora disponibile.

## Modifiche apportate, 24 novembre 2026: concessione e prova di accensione riuscita

Progetto SyncBeat, estensione del punto 4b autorizzata dall’utente con richiesta esplicita di eseguire la concessione. È stato eseguito `adb shell pm grant --user 0 com.example.syncbeat android.permission.WRITE_SECURE_SETTINGS`, senza errori. `dumpsys package` ha confermato `granted=true`.

**Esito: Debug wireless acceso dall’app e preparazione riuscita.** Prima dell’avvio `adb_wifi_enabled` risultava già `0`, con Wi-Fi collegato. Non è stato necessario spegnerlo dal PC. SyncBeat è stata arrestata e riaperta per osservare un avvio a freddo dell’app, senza riavviare il telefono.

| Ora nel logcat del telefono | Evento |
| --- | --- |
| 14:16:44.134 | `ADB_WIFI_ENABLE_REQUESTED`: l’app richiede l’attivazione. |
| 14:16:44.134 | Inizio della ricerca NSD. |
| 14:16:49.171 | Selezione di un solo candidato locale valido. |
| 14:16:49.233 | Connessione ADB autenticata. |
| 14:16:49.883 | `READY` ricevuto e chiusura della shell di bootstrap. |
| 14:16:49.891 | Autenticazione del canale locale confermata. |
| 14:16:49.893 | `APP_PREPARATION_READY`, dopo lo stato del servizio PID 19195. |

La lettura indipendente finale di `adb_wifi_enabled` ha restituito `1`. Dal primo evento a pronto: 5.759 ms. Una richiesta di attivazione, una ricerca e un tentativo di collegamento. Nessun `BEGIN_WRITE` o `RESTORE_WRITE`; permessi Zepp e flag coincidenti con la baseline e registro contenente soltanto `lease.lock`. Evidenze locali in `tools/zepp-transfer/debug-activation/`, escluse da Git.

La persistenza della concessione attraverso i riavvii è il comportamento dei permessi di sviluppo Android; il riavvio del telefono non è stato effettuato in questa prova. La riattivazione richiede l’apertura dell’app con Wi-Fi collegato. Il privilegio è più ampio della sola impostazione interessata ed è revocabile con `pm revoke`; il codice attuale espone soltanto l’attivazione del Debug wireless. Il trasporto ADB rimane autenticato tramite pairing/TLS. Questa prova non abilita né dimostra l’invio MP3 senza Wi-Fi, che resta subordinato al recupero del punto 5.4 e ai checkpoint B2/B3.

## Modifiche apportate, 24 novembre 2026: concessione guidata dal telefono

Progetto SyncBeat, estensione del punto 4b. L’utente ha chiesto una procedura utilizzabile dal telefono, con un unico pulsante e la descrizione breve concordata, senza un’ulteriore schermata o conferma. Ha autorizzato la revoca del privilegio esistente per verificare la nuova concessione. La revoca viene eseguita dopo avere pronto l’APK e riguarda soltanto `WRITE_SECURE_SETTINGS`; pairing ADB e configurazione dell’orologio vengono conservati.

- **Interfaccia.** La home espone **Impostazioni collegamento** anche quando il servizio è pronto. Nel dialogo esistente, **Abilita collegamento automatico** è accompagnato dal testo approvato. Il pulsante è l’unica azione di consenso; pairing e preparazione non lo attivano automaticamente. Una concessione già presente viene rilevata all’apertura della configurazione.
- **Concessione in Dart.** `EmbeddedAdb.authorizeAutomaticActivation` richiede l’azione esplicita, condivide un’eventuale richiesta contemporanea e usa una sola shell della connessione ADB autenticata. Il comando ha package, utente e permesso fissi: `pm grant --user 0 com.example.syncbeat android.permission.WRITE_SECURE_SETTINGS`. Non espone comandi o argomenti arbitrari. Una risposta di completamento non basta: prima del successo il codice richiede al ponte Android la conferma della concessione effettiva.
- **Controlli.** Il ponte nativo legge soltanto il permesso dell’app e il profilo Android. Sono ammessi il solo profilo principale e nessun trasferimento attivo. Errori, EOF e mancata conferma restano esiti di errore senza nuovo tentativo automatico. La nuova azione non esegue `BEGIN`, ripristini Zepp o invii musicali.
- **Verifiche locali.** Sono passati **200 test Flutter**, comprendenti consenso mancante, profilo non supportato, richiesta condivisa, concessione già presente, marker senza effettiva concessione, rifiuto del comando e test widget dell’unico pulsante senza popup aggiuntivi. Il percorso della prima configurazione completa di un nuovo utente resta distinto dalla prova sul pairing ADB già presente sul telefono.

L’analisi statica è pulita. È passata anche una regressione aggiuntiva per il marker seguito immediatamente da EOF della shell, caso normale del comando breve. L’APK release è stato compilato e installato con `adb install -r`, esito `Success`. Successivamente è stato eseguito il solo `pm revoke --user 0 com.example.syncbeat android.permission.WRITE_SECURE_SETTINGS`, autorizzato dall’utente, mantenendo Debug wireless acceso e pairing esistente.

All’apertura dopo la revoca, il processo app PID 17828 ha registrato `ADB_WIFI_MANUAL_ACTIVATION` alle 14:42:30.862 e `APP_PREPARATION_READY` alle 14:42:36.633. La lettura Android del privilegio ha confermato che non era concesso. L’apertura non ha quindi prodotto una concessione silenziosa. È stato chiesto all’utente di premere il pulsante sul telefono; la verifica dell’effettiva concessione da quel gesto resta pendente. Evidenze in `tools/zepp-transfer/guided-grant/`, escluse da Git.

## Modifiche apportate, 24 novembre 2026: concessione dal telefono e revisione prima del push

Progetto SyncBeat, punto 4b. L’utente ha premuto **Abilita collegamento automatico** sul telefono. Nel processo app PID 17828 sono comparsi `ADB_GRANT_REQUEST` alle 14:50:14.140 e `ADB_GRANT_VERIFIED` alle 14:50:14.207: circa 67 ms. La lettura indipendente Android ha confermato `WRITE_SECURE_SETTINGS: granted=true`. Dopo la revoca, nessun comando di concessione è stato eseguito dal PC. Il comando è partito dall’app attraverso la sessione ADB già autorizzata. Permessi Zepp e flag invariati, nessun `BEGIN`, registro con il solo `lease.lock`. **Esito della concessione guidata: riuscito** sul pairing esistente.

Alla richiesta di verifica prima del push è stata eseguita una revisione delle modifiche rispetto a `origin/main`. Sono stati corretti tre punti dell’interfaccia: selezione Jamendo/MP3 locale bloccata durante un’operazione, rimozione delle azioni sul vecchio download quando parte una nuova ricerca YouTube e una sola conferma visibile dopo la concessione. I test verificano anche il tentativo di cambiare selezione durante l’invio e l’assenza dell’azione di invio dopo una nuova ricerca.

La prima esecuzione completa ha rilevato inoltre un test instabile della libreria locale: usava ritardi reali di 100 ms per attendere il filesystem. Il test ora usa una directory vuota simulata per quella scansione, mantenendo la verifica dell’URI pubblicato, della riproduzione, dello stop e della rimozione dopo cancellazione esterna. Non è stato modificato il codice di caricamento della libreria.

La concessione dal telefono, la discovery e la preparazione sono state verificate sul dispositivo. Il primo pairing di una nuova installazione e l’invio reale dal popup di download restano verifiche distinte. L’invio musicale senza Wi-Fi resta da implementare nei checkpoint B2/B3, con il recupero del punto 5.4. La revisione non equivale alla convalida di quelle funzionalità successive. Nessun push o merge è stato eseguito dall’agente.

### Controlli finali e operazione osservata durante la revisione

La suite finale comprende **201 test Flutter superati**, con **56 test JVM superati**, analisi statica pulita e APK release compilato. I controlli di regressione dei popup passano dopo le correzioni. Il fetch di `origin` ha confermato che `origin/main` è un antenato del branch di lavoro, senza commit remoti mancanti nel branch.

Durante la revisione l’utente ha avviato autonomamente un trasferimento MP3 nel processo app PID 19846. Il campionamento ha rilevato permessi Zepp temporaneamente negati e registro `restore` presente: era un’operazione attiva, quindi l’installazione dell’APK finale è stata rimandata. Nei log: `RUN_UPLOAD` alle 14:53:18.404; `RUN_FINALLY completed=true primaryFailed=false` alle 14:55:36.088; `RESTORE_WRITE` alle 14:55:36.093 e `RESTORE_OK` alle 14:55:37.107. Il codice nativo ha riportato **Invio MP3 riuscita dopo 143882 ms** alle 14:55:37.115. L’agente non ha avviato né interrotto quell’invio. Non è stata verificata la riproduzione del nuovo brano sull’orologio.

Dopo il completamento, tutti i permessi Zepp e i flag coincidevano nuovamente con la baseline; il registro conteneva soltanto `lease.lock`. È stato quindi installato l’APK finale. `WRITE_SECURE_SETTINGS` è rimasto `granted=true` attraverso l’aggiornamento, senza ripetere la concessione dal PC. Le evidenze della revisione e dell’operazione sono in `tools/zepp-transfer/pre-main/`, escluse da Git.

L’apertura dell’APK finale ha registrato `ADB_WIFI_ALREADY_ENABLED` alle 14:56:39.903 e `APP_PREPARATION_READY` alle 14:56:45.321, senza alcun `ADB_GRANT_REQUEST`. Il percorso di preparazione funziona quindi anche dopo l’aggiornamento e riusa il privilegio concesso dal telefono. Nel processo del trasferimento era stato osservato un download alle 14:52:12, precedente all’invio; la traccia del trasferimento rimane distinta dalla conferma di riproduzione sul lettore dell’orologio.

## Modifiche apportate, 24 novembre 2026: recupero chiave dall’account Zepp

L’utente ha chiesto di verificare la fattibilità del recupero guidato e integrarlo
se praticabile. È stato verificato il codice pubblico MIT huami-token e il
corrispondente scambio Android di AmazToken. È stata integrata un’azione esplicita
**Collega account Zepp** nella configurazione esistente, compresa quella aperta
dal download. Il recupero usa email/password direttamente verso HTTPS Zepp e
salva solo l’`auth_key` corrispondente all’intero indirizzo dell’orologio scelto,
senza mostrare la chiave, persistere credenziali, modificare musica/permessi o
avviare invii. Resta l’inserimento manuale. Endpoint e autenticazione non sono
un’interfaccia pubblica garantita dal produttore; accessi social e verifiche
aggiuntive non sono implementati.

Superati **214 test Flutter e 56 test JVM**, analisi statica pulita e compilazione
release. Il nuovo APK è stato installato (`Success`) e conserva il privilegio
Android già concesso. Il recupero reale non è ancora provato: l’utente non ricorda
il metodo di accesso e deve inserire le proprie credenziali sul telefono. Non
sono state chieste password in chat né eseguiti accessi per suo conto.

L’apertura ha inoltre rilevato un errore nel collegamento ADB dopo la selezione
di un unico candidato locale: `ADB_DISCOVERY_SELECTED`, `ADB_AUTO_CONNECT_ERROR`,
`APP_PREPARATION_ERROR`. Non è un successo del bootstrap e non va confuso con i
checkpoint precedenti riusciti. La modifica account non cambia quel percorso e
non lo usa per recuperare la chiave; la causa del nuovo esito resta da chiarire.
Dettagli e checkpoint in [fattibilità account](zepp-account-fattibilita.md).

## Verifica sul telefono, 24 novembre 2026: chiave Zepp recuperata

Dopo la prova richiesta l’utente ha comunicato **fatto**. I log del processo
PID 30294 confermano `ACCOUNT_TOKENS_OK`, `ACCOUNT_LOGIN_OK`,
`ACCOUNT_KEY_MATCHED`, `ACCOUNT_LOGOUT_OK`, `ACCOUNT_KEY_MATCHES_SAVED` e
`ACCOUNT_KEY_SAVED`, in circa 5,14 secondi complessivi. Il recupero ha quindi
restituito la stessa chiave valida già usata per questo orologio, ha chiuso
correttamente la sessione temporanea e ha completato il salvataggio sicuro.
Sono state lette solo queste fasi: nessuna credenziale o chiave è stata esposta.
Questo esito supera il precedente checkpoint pendente del recupero account,
senza estenderlo ad altri dispositivi o account. Nessun invio è stato avviato.

È stato chiesto un ultimo controllo della sincronizzazione nell’app Zepp. La
conferma dell’utente è pendente. Nella stessa apertura il collegamento ADB ha
ancora riportato `APP_PREPARATION_ERROR` prima del recupero HTTPS: questo errore
rimane aperto e non è risolto dal successo del recupero chiave.

## Correzione del 25 novembre 2026: logout Zepp e diagnostica della connessione

L’utente ha verificato che il recupero chiave della prima build ha causato il
logout dell’app Zepp e ha confermato l’errore ADB nella preparazione automatica.
La prova del 24 novembre dimostrava il recupero della chiave, non la conservazione
della sessione Zepp. È stata trovata una fonte primaria di implementazione
(dreeve-zepp-connector) che documenta lo stesso effetto del login mobile e usa
un login web per evitarlo. Il codice SyncBeat ora usa identità e scambio web,
non esegue più il logout remoto e non ripiega sul login mobile. L’assenza di
interferenza con Zepp deve ancora essere verificata da questo utente nella nuova
build. Password e token restano soltanto in memoria.

La dipendenza ADB restituiva un errore generico: ora un adattatore attorno al suo
unico tentativo distingue rifiuto TCP, timeout, errore di rete e autenticazione
ADB/TLS non confermata, mostrando un messaggio pertinente. Intercetta soltanto
la stampa grezza di errore della dipendenza, registrando codici fissi. Non sono
stati aggiunti probe, nuovi collegamenti, retry, reset di chiavi o modifiche al
protocollo musicale. La causa del problema del telefono non è ancora risolta.

I **218 test Flutter** passano, inclusi identità web per l’autenticazione, assenza
del logout e di fallback mobile anche dopo errore, oltre a classificazione e
singolo tentativo ADB. ADB vede al momento un telefono M2006C3LVG, diverso dallo
Xiaomi 15T già usato: è stata chiesta conferma prima di installare o modificare
il dispositivo. Dettagli in [recupero account](zepp-account-fattibilita.md).

L’analisi statica finale è senza segnalazioni e l’APK release correttivo è stato
compilato (177,2 MB). Non è stato installato sul telefono M2006C3LVG: la scelta
del dispositivo di verifica è ancora da confermare. Nessun accesso account,
concessione/revoca di permessi o invio musicale è stato eseguito sul dispositivo
diverso. La diagnosi fisica ADB e la verifica della sessione Zepp restano pendenti.

## Verifica del 25 novembre 2026: avvio sullo Xiaomi 15T corretto

L’utente ha confermato che il M2006C3LVG non era il suo telefono. Al nuovo
controllo ADB ha rilevato lo Xiaomi 15T `goya_eea`, usato per le prove precedenti.
Il privilegio SyncBeat risultava già concesso, i tre permessi Bluetooth Zepp
concessi e `adb_wifi_enabled=0`. Nessun invio risultava in corso. L’APK correttivo
è stato installato (`Success`) e l’app aperta senza ripetere concessioni.

Nel processo PID 11589: `ADB_WIFI_ENABLE_REQUESTED`, discovery di tre servizi con
un solo candidato locale, `ADB_AUTO_CONNECTED`, `DIRECT_BOOTSTRAP_READY`,
`DIRECT_BOOTSTRAP_CLOSED`, `DIRECT_STATUS_OK pid=24568`, quindi
`APP_PREPARATION_READY`. Dall’avvio della richiesta al servizio pronto sono
trascorsi circa **5,58 secondi**. La lettura Android ha confermato il flag passato
da 0 a 1. Un solo tentativo, nessun invio o comando di sospensione Zepp.

La preparazione automatica è dunque riuscita in questa prova sul telefono
corretto. Il vecchio guasto non è stato riprodotto e non si attribuisce la
risoluzione a una modifica del trasporto: l’incremento distingue gli errori ma
non cambia porte, identità o numero dei tentativi. È stata richiesta la verifica
separata del recupero account web e della permanenza della sessione Zepp.

## Verifica del 25 novembre 2026: sessione Zepp conservata, rifiuto ADB riprodotto

Il pulsante account segnalato come disabilitato dipendeva dal campo **Orologio**
ancora senza selezione, con elenco già caricato. È stata selezionata l’unica voce
Active 3 e l’utente ha eseguito il nuovo recupero. Nel processo PID 11589 sono
comparsi `ACCOUNT_WEB_LOGIN_OK`, `ACCOUNT_KEY_MATCHED`,
`ACCOUNT_KEY_MATCHES_SAVED` e `ACCOUNT_KEY_SAVED`, circa 0,57 secondi dall’avvio.
La chiave coincide con quella funzionante; nessun valore è stato esposto.
L’utente ha poi confermato **«Sì, sincronizza senza nuovo accesso»** in Zepp.
Il checkpoint della correzione del logout è dunque superato su questo account.

Il problema ADB si è invece ripresentato nelle riaperture: candidato unico
selezionato e `ADB_CONNECT_REFUSED` prima di `APP_PREPARATION_ERROR`, anche con
flag già attivo. La prima apertura riuscita non dimostra la risoluzione del
difetto. Ora il rifiuto TCP è distinto da timeout e problemi di autenticazione;
non prova che manchi il privilegio Android o che il pairing vada rifatto.
La presenza di più pubblicazioni del telefono con porte diverse nella discovery
del PC rende da verificare una possibile pubblicazione obsoleta. La causa non è
ancora dimostrata. Nessun retry, reset, invio o modifica del protocollo musicale
è stato introdotto durante questo checkpoint.

## Intervento del 25 novembre 2026: ricerca aggiornata e causa TLS individuata

Su richiesta esplicita di risolvere il problema ADB è stata mantenuta una sola
connessione per apertura/gesto e nessuna modifica al protocollo musicale.

**Discovery.** Su Android 14+ la risoluzione singola è stata sostituita da
`NsdManager.registerServiceInfoCallback`: durante la finestra di ricerca gli
aggiornamenti sostituiscono la porta precedente e le perdite invalidano il dato.
Android 11–13 mantiene la risoluzione compatibile. `AdbDiscoveryEntries` usa
generazioni per impedire che una callback tardiva resusciti una pubblicazione
persa; la fine della ricerca rimuove tutte le registrazioni. Restano i controlli
sul telefono locale e sull’unicità del candidato, il collegamento a localhost e
le finestre di 5/10/12 secondi già usate. Non sono stati aggiunti probe o retry
al percorso applicativo. Fonte API:
https://developer.android.com/reference/android/net/nsd/NsdManager .

**Verifica della causa.** Una pubblicazione obsoleta era un’ipotesi iniziale e la
sola modifica della discovery non ha risolto tutti gli avvii. Tramite USB è stata
confrontata privatamente la porta indicata dalle impostazioni con il servizio
Android; un unico controllo TCP diagnostico su quella porta ha confermato che
localhost rispondeva. Un helper temporaneo `app_process`, non incluso nell’APK,
ha letto soltanto porta e conteggi dal servizio Android, senza concessioni o
modifiche al servizio. Non sono stati letti o mostrati valori di chiavi.

La libreria nascondeva l’errore arrivato *dopo* il completamento iniziale TLS.
Una variante temporanea, confinata in `.dart_tool`, ha emesso esclusivamente
codici di fase, senza abilitare il verbose o registrare pacchetti. Nel processo
PID 8845 sono stati osservati `TCP_CONNECTED`, `ADB_STLS_RECEIVED`,
`TLS_CONTEXT_READY`, `TLS_ESTABLISHED`, `TLS_SOCKET_ERROR`, quindi
**`TLS_CERTIFICATE_UNKNOWN`** e chiusura del canale. L’app riceveva infine
`ADB_HANDSHAKE_REJECTED`. Questo avvio ha raggiunto la porta e avviato TLS:
Android non ha riconosciuto il certificato del client come autorizzato.
Non è stato dimostrato quando o perché quell’autorizzazione abbia cessato di
essere valida; non va confusa con `WRITE_SECURE_SETTINGS`, che resta concesso.
Riferimento del controllo dei client in adbd:
https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/master/daemon/auth.cpp .

**Ripristino preparato.** Il messaggio di autenticazione indica ora
**Configura collegamento → Abbina dalla notifica**. È stato chiesto all’utente
di ripristinare una volta l’abbinamento inserendo il codice direttamente nella
notifica; il codice non viene chiesto in chat. Non sono stati revocati altri
host, cancellate le chiavi dell’app o disattivati i timeout di sicurezza Android.
La verifica dopo questo passaggio resta pendente.

**Build definitiva.** La variante diagnostica e l’override sono stati rimossi:
la configurazione dei pacchetti torna a `flutter_adb 1.0.0` originale e nel
binario finale non compare il marcatore diagnostico temporaneo. Superati
**218 test Flutter e 61 test JVM**, analisi statica senza segnalazioni e build
release. L’APK definitivo è stato installato sullo Xiaomi 15T con `Success`.
Nessun invio musicale o test di revoca/ripristino Zepp è stato avviato.

## Verifica dopo il nuovo abbinamento, 25 novembre 2026

L’utente ha confermato l’abbinamento dalla notifica. Nel processo PID 10543
sono poi comparsi `ADB_AUTO_CONNECTED`, `DIRECT_BOOTSTRAP_READY`,
`DIRECT_BOOTSTRAP_CLOSED`, `DIRECT_STATUS_OK pid=15123` e
`APP_PREPARATION_READY`: l’autenticazione TLS è tornata funzionante senza
cancellare l’identità dell’app o modificare il privilegio Android.

Sono riusciti due avvii da processo chiuso: Debug wireless già attivo
(PID 12492) e attivazione automatica da flag spento (PID 14458). Ciascuno
ha effettuato una sola discovery, una connessione autenticata e una richiesta
di stato, senza musica o sospensione dei permessi Zepp.

**Riapertura ancora difettosa.** Nello stesso processo PID 14458, dopo il
passaggio alle impostazioni e lo spegnimento del Debug wireless, il ritorno
nell’app ha riattivato il flag ma ha selezionato una porta chiusa, con
`ADB_CONNECT_REFUSED`. Il successo dei due avvii precedenti non chiude quindi
il difetto automatico.

I controlli USB, esterni all’APK, hanno dimostrato quattro pubblicazioni locali
con lo stesso nome base: una sola porta corrisponde al servizio Android attuale.
Quella attuale porta un suffisso DNS-SD ` (N)`, mentre il vecchio filtro Dart
accettava soltanto il nome senza suffisso. Anche una richiesta mDNS diretta
ha ricevuto le quattro pubblicazioni: aggiornare le callback o attendere una
nuova risposta non basta a distinguerle. Nessuna scansione di porte o prova
TCP multipla è stata aggiunta nell’app.

**Correzione del filtro.** I suffissi Android sono ora inclusi tra i candidati.
Con più pubblicazioni l’app restituisce `ADB_DISCOVERY_AMBIGUOUS` prima di
aprire il socket, invece di scegliere erroneamente l’unico nome senza suffisso.
Due regressioni verificano il nome rinominato e la coesistenza con annunci
precedenti. Il messaggio spiega che Android annuncia più porte e che non è
possibile identificare con certezza quella attuale. Non viene scelto il suffisso
numericamente maggiore e non viene provata la porta salvata.

Un riavvio del solo servizio ADB via USB ha eliminato le vecchie pubblicazioni
e l’avvio successivo (PID 15885) è riuscito con una connessione e uno stato.
La riapertura dopo un nuovo spegnimento ha però riprodotto l’ambiguità, anche
attendendo prima la conferma dal servizio Android della porta non disponibile
(circa 1,16 secondi). Il riavvio del servizio è stato un controllo diagnostico
dal PC, **non una soluzione implementata nell’app**.

La build release con il filtro corretto è stata installata con `Success`.
**220 test Flutter superati**, analisi senza segnalazioni; restano validi i
61 test JVM della modifica nativa già verificata. Dipendenza originale
`flutter_adb 1.0.0`, nessuna variante diagnostica nel pacchetto.
Il pairing è verificato; la preparazione automatica dopo cambio della porta
resta aperta e non è dichiarata risolta. Una verifica dopo riavvio completo
Android resta da eseguire.

## Prova del flusso da prima installazione: preparazione, 25 novembre 2026

L’utente propone una prova senza dati SyncBeat preesistenti prima di proseguire
gli sviluppi. La prova è preparata, **non ancora eseguita**: nessun dato è stato
cancellato per questa richiesta. Prima si conclude il checkpoint ADB dopo il
riavvio, conservando lo stato utile alla diagnosi.

Il punto di partenza dovrà avere archivio sicuro, preferenze e cache SyncBeat
vuoti, nuova identità ADB senza abbinamento precedente e autorizzazione
`WRITE_SECURE_SETTINGS` assente. Nessun trasferimento o ripristino dei permessi
Zepp deve risultare pendente prima del reset. Una semplice reinstallazione
con aggiornamento non costituisce questa prova.

L’azzeramento dei dati dell’app elimina anche eventuali file nello staging
privato: prima di proporlo come azione finale occorre identificare i file da
conservare e verificarne una copia accessibile fuori dai dati privati.
Non si cancellano sorgenti musicali, file nei Download, dati/account di Zepp
o abbinamento Bluetooth dell’orologio. Le vecchie autorizzazioni ADB di altri
host, incluso il PC diagnostico, non vanno revocate. La nuova identità dell’app
deve comunque richiedere il proprio primo abbinamento.

Checkpoint nell’ordine:

1. **Primo avvio e collegamento.** Dalle normali schermate dell’app, attivazione
   manuale iniziale del Debug wireless, abbinamento dalla notifica, scoperta
   della porta e concessione facoltativa guidata del collegamento automatico.
   Nessun inserimento manuale della porta né concessione dal PC per superare
   un blocco del percorso utente.
2. **Configurazione orologio.** Permessi Bluetooth, scelta dell’orologio e
   recupero della chiave tramite accesso web. Nessun riuso della chiave salvata.
   Confermare che Zepp resti autenticata e sincronizzi.
3. **Riaperture.** Preparazione all’apertura con debug già attivo, poi dopo
   spegnimento del debug e dopo riavvio del telefono. Una sola connessione
   per gesto; nessun trasferimento o sospensione durante la preparazione.
4. **Sospensione e ripristino senza file.** Eseguire soltanto dopo i checkpoint
   precedenti e verificare il ritorno effettivo dei permessi Zepp.
5. **Download e invio esplicito.** Scaricare un file autorizzato, inviarlo dalla
   schermata Download con il normale pulsante e verificare riproduzione
   sull’orologio e successiva sincronizzazione Zepp. Nessun invio automatico.

Per ogni checkpoint si annotano passaggi visibili, esito e punti che richiedono
assistenza tecnica. L’agente legge log e risultati; all’utente restano accesso
account, codice Android, sblocco e ascolto sull’orologio. Un blocco non viene
aggirato con configurazioni manuali dal PC: si corregge e si ripete il relativo
checkpoint prima di passare agli sviluppi successivi. La prova di invio senza
Wi-Fi resta un incremento separato, non già implementato.

## Causa delle pubblicazioni obsolete e correzione verificata, 25 novembre 2026

La diagnosi successiva supera l’ipotesi di un problema non distinguibile della
sola discovery. Con SyncBeat ferma, spegnimento e riattivazione lasciano un solo
servizio corrente. Dopo il bootstrap B1, la stessa sequenza ne lascia due;
quello vecchio scompare alla chiusura del processo dell’app e del relativo
servizio locale.

**Risorsa ereditata.** Sul telefono, `app_process` riceve da adbd un descrittore
di socket Unix senza `CLOEXEC`, collegato a `/dev/socket/mdnsd`. Il processo B1
persistente tratteneva questa copia: la chiusura del riferimento di adbd non
liberava quindi la vecchia pubblicazione. Un processo diagnostico separato ha
riprodotto due servizi mantenendo il descrittore e un solo servizio corrente
chiudendo quella copia. La shell diagnostica deve usare `exec`, come il bootstrap
reale, perché anche una shell intermedia in attesa può trattenere una copia.
Questi controlli non aprono connessioni TCP né leggono chiavi.

**Implementazione.** `InheritedAdbResources` viene chiamato all’ingresso di
`ZeppAdbLeaseServer.main`, dopo il controllo UID shell/root e prima di entrambi
i percorsi persistenti. Esclude stdin/stdout/stderr e descrittori con
`O_CLOEXEC`; per gli altri verifica su una copia temporanea che il peer sia
esattamente `/dev/socket/mdnsd`. Chiude esclusivamente il descrittore ereditato
del figlio, senza `shutdown` del socket condiviso con adbd. Non vengono chiusi
socket creati dal servizio o risorse ART. L’ispezione del peer usa il getter
framework `UnixSocketAddress.getSunPath` nel solo processo shell, senza nuovi
privilegi dell’app o accessi al gestore ADB. Errori di chiusura non vengono
ignorati prima di annunciare READY. Il marcatore registra solo
`BOOTSTRAP_INHERITED_MDNS_CLOSED count=N`.

Il controllo dei flag usa `O_CLOEXEC` per `/proc/self/fdinfo`, distinto da
`FD_CLOEXEC` di `fcntl`. L’ispezione usa `ParcelFileDescriptor.fromFd`: adottare
un descrittore gestito da ART può causare un abort fdsan. Un primo helper
diagnostico, esterno all’APK, è terminato proprio per quel controllo; è stato
corretto prima dell’implementazione e non ha modificato dati o l’app installata.

**Interferenza dell’installazione USB.** Dopo `adb install -r` completato con
`Success`, anche il bridge persistente di sistema `abb` conservava un socket
ereditato e impediva il primo avvio del test. È stato identificato e chiuso una
sola volta, verificando prima processo e nome. Non è un’azione eseguita dall’app.
Tutti i cicli seguenti sono avvenuti senza altri riavvii di ADB o pulizie dal PC.
La correzione riguarda le risorse dei processi avviati da SyncBeat; non forza la
chiusura di risorse appartenenti ad altri processi ADB. Il filtro delle ambiguità
resta attivo.

**Verifiche della release installata.**

- Primo avvio PID 24846 e successiva riapertura con cambio di porta: pronti;
  dopo la riapertura un solo servizio, corrispondente alla porta Android.
- Avvio PID 28109 con debug acceso e due ulteriori spegnimenti/riaperture:
  tutti pronti con una discovery e una connessione autenticata per gesto.
  Nei due cambi restano identici il processo dell’app e il PID del servizio
  diretto: B1 sopravvive e viene riusato, senza un nuovo bootstrap.
- Riapertura già pronta: nessuna nuova discovery o connessione.
- Avvio PID 28305 con debug spento: `ADB_WIFI_ENABLE_REQUESTED`,
  `ADB_AUTO_CONNECTED`, bootstrap READY/chiusura shell, stato diretto del
  servizio PID 32052 e `APP_PREPARATION_READY`. Un solo servizio corrente.
- I tre bootstrap finali hanno registrato ciascuno la chiusura di una risorsa
  mDNS ereditata. I permessi Bluetooth Zepp risultano ancora tutti concessi e
  `WRITE_SECURE_SETTINGS` resta concesso a SyncBeat.

**65 test JVM superati**, inclusi quattro nuovi controlli di selezione delle
risorse, mancata doppia chiusura, propagazione dell’errore e corretta maschera
dei flag. Analisi statica pulita e build release riuscita. Resta valida la suite
Flutter da 220 test della modifica precedente, senza altre modifiche Dart in
questo intervento. APK installato con `Success`.

Il guasto riprodotto nei cambi di porta dell’app è quindi corretto e verificato
su questo telefono. Non sono stati cambiati protocollo musicale, comandi di
sospensione/ripristino, identità ADB o numero di tentativi. Nessun invio è stato
eseguito. L’utente ha successivamente confermato che le ultime prove sono
avvenute dopo il suo riavvio completo del telefono: è quindi verificato anche
il funzionamento dopo riavvio, con pairing e privilegio Android conservati.
La preparazione è avvenuta aprendo l’app; non è una prova di avvio automatico
al boot. Resta la prova da prima installazione proposta dall’utente; nessun
dato è stato azzerato. Questa conferma supera le precedenti note di verifica
pendente dopo il riavvio.
