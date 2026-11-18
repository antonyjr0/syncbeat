# Prove Zepp su telefono — 18 novembre 2026

Codice di prova `4509efcf491b5954193b8eb66a34945e5c3cb217`, ramo `experiment/zepp-native-music`. Obiettivo del ramo A: verificare il collegamento diretto a Zepp attiva e, se riesce, tentare l'importazione con gestione automatica disattivata.

## Preparazione

| Controllo | Esito |
| --- | --- |
| ADB e selezione del telefono | ADB 35.0.2. Due telefoni USB autorizzati. Selezionato solo il modello `25069PTEBG` usato nelle prove precedenti. |
| Ambiente | Windows. Telefono Android 16, API 36, HyperOS 3.0. Zepp `10.10.5-play`. |
| Provenienza APK iniziale | L'APK installato coincideva con la release locale del 17 novembre. La corrispondenza con il commit di prova non era verificabile. |
| Compilazione e aggiornamento | Release compilata dal commit di prova. Gradle ha completato la build dopo il fallback dal daemon Kotlin. Aggiornamento in-place riuscito con `adb install -r`. SHA-256 dell'APK installato uguale a quello appena compilato. |
| Suite JVM del protocollo | 23 superati, 0 falliti, 0 saltati. |
| Suite JVM dei permessi | 8 superati, 0 falliti, 0 saltati. |

Per entrambe le suite JVM è stato usato `:app:testDebugUnitTest`. Il tentativo iniziale con `:app:testReleaseUnitTest` si è fermato perché il task release non è disponibile.

## Stato iniziale dei permessi Zepp

Nel profilo principale, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` e `BLUETOOTH_ADVERTISE` risultavano tutti concessi, con flag `USER_SET`, `USER_SENSITIVE_WHEN_GRANTED` e `USER_SENSITIVE_WHEN_DENIED`.

## Prove sul dispositivo

| Prova | Esito |
| --- | --- |
| Navigazione da PC | ADB leggeva la schermata e poteva portare le app in primo piano. I tocchi simulati sui pulsanti osservati non facevano avanzare l'interfaccia. Antonio ha aperto e usato il dialogo. |
| Ramo A, verifica collegamento senza invio | Una sola esecuzione, con **Gestisci automaticamente Zepp** su OFF e chiave già presente nell'archivio dell'app. La connessione Bluetooth Classic è fallita dopo **836 ms** con `IOException: read failed, socket might closed or timeout, read ret: -1`, prima dell'autenticazione. Antonio ha poi chiarito che il Bluetooth era spento durante la selezione dell'orologio. Lo stato del Bluetooth e della connessione Zepp al momento della verifica resta incerto. |
| Ramo A, invio MP3 | Non eseguito perché la verifica di collegamento è fallita. La richiesta di importazione e il fix dei metadati non sono stati esercitati. |
| Ramo B, sospensione e ripristino | Non eseguito. Il debug wireless risultava disattivato. Va prima ripetuto il ramo A con la connessione Zepp verificata. |
| Presenza e riproduzione del brano | Non verificabili in questa prova, poiché l'invio non è iniziato. |
| Funzionamento simultaneo | Non verificato. Richiede un invio in corso e un riscontro sul funzionamento di Zepp durante l'invio. |
| Permessi Zepp a fine prova | Tutti e tre i valori e i relativi flag coincidono con la lettura iniziale. Nessun avviso di ripristino pendente osservato nel dialogo. |
| Connessione e sincronizzazione Zepp | Dopo la prova, Antonio ha confermato che Zepp risultava collegata all'Active 3 Premium. Una sincronizzazione completa e lo stato della connessione prima del tentativo non sono stati confermati separatamente. |

Il primo tentativo si è fermato all'apertura della connessione Classic. Il risultato è inconcludente sulla coesistenza con Zepp e lascia da verificare lo stato `5`, osservato in precedenza nella fase di importazione.

## Verifica successiva dello stato Bluetooth

- Alle 08:24:08 Android ha registrato una richiesta di disattivazione da `com.android.systemui`, prima dell'inizio della sessione di test. Alle 08:24:13 risulta una richiesta di riattivazione da `android` con motivazione `RESTARTED`; queste sono richieste e non attestano da sole lo stato finale dell'adattatore.
- Alle 09:38:01 Android ha registrato una richiesta di attivazione da `com.android.systemui`. Alle 09:38:16 SyncBeat ha registrato il fallimento della connessione Classic. La connessione di Zepp prima del tentativo resta da confermare.
- Nelle richieste Bluetooth registrate per il 18 novembre non compare SyncBeat. Il codice della selezione controlla lo stato dell'adattatore e il collegamento può interrompere una scansione in corso. La sospensione opzionale agisce sui permessi di Zepp.

## Ramo A, seconda verifica alle 09:45

Antonio ha eseguito la prova dal telefono. Dal PC sono state effettuate solo letture. L'adattatore Bluetooth risultava acceso continuativamente dalle 09:38 circa.

| Controllo | Esito |
| --- | --- |
| Verifica collegamento | Alle 09:45:06 la connessione Classic è fallita dopo **231 ms** con `IOException: read failed, socket might closed or timeout, read ret: -1`, prima dell'autenticazione. |
| Invio MP3 | Nessun invio osservato. Lo stato `5` e il fix ai metadati rimangono da verificare. |
| Permessi Zepp dopo la prova | Tutti e tre concessi, con gli stessi flag della lettura iniziale. |
| Connessione e sincronizzazione Zepp | In attesa del riscontro di Antonio sulle condizioni prima e dopo la prova. |

L'errore Classic si è ripresentato con l'adattatore Bluetooth acceso. La causa della chiusura del socket resta da identificare.

## Ramo A, terza verifica alle 09:46

Nuovo tentativo manuale di Antonio. Alle 09:46:40 la connessione Classic è fallita dopo **585 ms**, con lo stesso `IOException: read failed, socket might closed or timeout, read ret: -1`. Il Bluetooth risultava ancora acceso. La prova si è fermata prima dell'autenticazione e dell'invio. La sincronizzazione Zepp precedente al tentativo resta da confermare.

## Verifica in alternanza con sospensione manuale alle 09:49

Antonio ha tolto a Zepp il permesso **Dispositivi nelle vicinanze** dalle impostazioni Android e ha avviato una verifica senza invio. La lettura da PC ha confermato che i tre permessi Bluetooth di Zepp erano negati. Alle 09:49:19 SyncBeat ha registrato l'apertura del socket Classic in **693 ms**. Antonio ha confermato il messaggio di autenticazione riuscita e servizio `music` presente. Questa prova conferma il collegamento in alternanza fino alla verifica del servizio.

## Invio MP3 in alternanza alle 09:51

| Controllo | Esito |
| --- | --- |
| Connessione e autenticazione | Nuova connessione Classic in **209 ms** alle 09:51:39. Autenticazione riuscita, osservata nel dialogo. |
| Richiesta di importazione e blocchi audio | Richiesta accettata e tutti i blocchi confermati. Dialogo finale **Ultimo blocco confermato**. Il codice `5` non si è ripresentato. |
| Input, presenza e riproduzione | Antonio ha confermato che il brano funziona sul lettore dell'orologio. L'identità del file rispetto alla prova precedente e i metadati esatti non sono stati confermati separatamente. |
| Ripristino e funzionamento Zepp | Verificato via ADB che i tre permessi e i relativi flag coincidono di nuovo con lo stato iniziale. Antonio ha confermato che Zepp è tornata a funzionare dopo una breve attesa. Durata esatta e completamento di una nuova sincronizzazione non registrati. |

Esito su hardware: invio diretto, riproduzione nel lettore originale e ritorno al funzionamento di Zepp dopo la sospensione manuale. La causa del precedente codice `5` resta indeterminata. La coesistenza durante l'invio e la gestione automatica tramite ADB interno restano da verificare.

## Alternative per evitare di ripetere i passaggi manuali

Obiettivo: dal solo telefono, dopo l'eventuale configurazione iniziale, avviare l'invio senza sospendere Zepp a mano, reinserire codici o porte, o riattivare il debug. Vincoli attuali: telefono senza root, nessun PC o cavo per l'uso della funzione, nessuna app aggiuntiva.

Stato della modifica alla notifica: APK release compilato, analisi dei due file Dart superata, 8 test Flutter ADB/Zepp superati. Restano da provare sullo Xiaomi la comparsa della notifica, la risposta con Impostazioni aperte, l'abbinamento e l'invio automatico.

Scorciatoia a Debug wireless: l'intent delle preferenze del riquadro rapido ha aperto `WirelessDebuggingFragment` sullo Xiaomi nella prova via ADB. SyncBeat usa lo stesso intent per **Apri Debug wireless** e **Abbina dalla notifica**. Se l'attività è assente o Android ne rifiuta l'apertura, usa le Opzioni sviluppatore. Rimane da provare il percorso completo partendo dal pulsante di SyncBeat.

### Sonda BLE durante la preparazione dell'alternanza automatica

Antonio ha confermato di essere riuscito a configurare il debug wireless e ha riferito un primo tentativo fallito, il cui messaggio resta sconosciuto. Per la ripetizione ha riportato «Il collegamento BLE parallelo non risponde entro 20 secondi». Il codice associa questo messaggio alla sonda **Verifica connessione parallela (senza invio)**. La sonda si è fermata in BLE e il log non mostra una nuova apertura Classic. Dopo il timeout i tre permessi Zepp e i relativi flag coincidevano con lo stato iniziale. L'alternanza automatica resta da provare con **Prova sospensione e ripristino (senza file)**.

### Diagnostica per i prossimi tentativi

Il tag Android `SyncBeatZepp` riporta l'avvio, la durata e l'esito della sonda BLE, il risultato della prova di sospensione e ripristino e le fasi del percorso Classic. Per l'importazione registra anche l'eventuale codice di rifiuto dell'orologio. I messaggi riportano stati dell'app e codici numerici. I risultati di riproduzione sul lettore e di sincronizzazione di Zepp vanno confermati a parte.

Per ogni nuovo tentativo annotare ora, pulsante, stato della gestione automatica, ultima fase raggiunta, durata, esito e permessi Zepp dopo il tentativo. La diagnostica aggiunta vale per le prove eseguite con la nuova build.

### Prova automatica di sospensione e ripristino alle 11:34

| Controllo | Esito |
| --- | --- |
| Ripristino preliminare | Alle 11:34:29 `restoreZeppPermissions` è terminato in 0 ms. La riga indica il completamento della chiamata e non conferma che ci fosse uno stato da ripristinare. |
| Prova senza file | Alle 11:34:37 l'app ha avviato `testZeppPermissions`. Alle 11:35:18 la chiamata è fallita dopo **41,130 s** con `IOException`. |
| Messaggio nel dialogo | «Ripristino Zepp non confermato. Riconnetti il debug wireless e premi Ripristina permessi Zepp.» Il messaggio riguarda il ripristino; resta da accertare se la sospensione iniziale sia avvenuta. |
| Verifica indipendente | Dopo la prova, i tre permessi Bluetooth di Zepp erano tutti concessi e i flag coincidevano con quelli iniziali. Antonio ha confermato che **Dispositivi nelle vicinanze** risultava concesso nelle impostazioni Android. Il debug wireless risultava attivo. |

L'automazione non ha confermato il ciclo. Nessun invio era previsto in questa prova. Prima di un nuovo tentativo, chiarire lo stato di ripristino nel dialogo e verificare che Zepp funzioni.

### Riconciliazione e diagnostica nella build successiva

- Il refresh legge lo stato locale e può interrogare il registro solo tramite una connessione al servizio già aperta. La lettura non avvia il servizio e non richiede un ripristino. I log indicano gli esiti e la durata delle fasi ADB. Se falliscono sia la sospensione sia il ripristino, l'app mostra entrambi.
- L'app salva l'identità del ciclo prima di inviare `BEGIN`. Il servizio salva la baseline come `OPEN` prima di sospendere i permessi e, dopo averla verificata, salva `CLOSED_VERIFIED` nello stesso registro atomico. L'app chiude il proprio obbligo solo dopo una risposta riferita al ciclo atteso. Il servizio conserva la ricevuta fino a quando può sostituirla con il successivo ciclo riconciliato.
- Un vecchio marker privo di registro può essere chiuso con la conferma manuale esplicita. Questo esito resta distinto dal ripristino verificato. Un registro aperto o illeggibile richiede una verifica ulteriore.
- Validazione locale: 9 test Flutter ADB/Zepp, compresa la conferma manuale, e 31 test JVM Zepp. Restano da provare il nuovo registro con una risposta persa o un'interruzione reale e il test automatico senza file sullo Xiaomi.

Dopo l'installazione, Antonio ha segnalato un errore premendo **Ripristina permessi Zepp**. Alla lettura da PC il debug wireless risultava spento e i tre permessi Bluetooth di Zepp e i relativi flag coincidevano con lo stato iniziale. Nella directory del servizio non risultavano il registro base né il suo backup. Il messaggio esatto del tentativo non era disponibile nei log rimasti sul telefono. La lettura esterna non permette di confermare il ciclo nell'app.

| Tentativo manuale | Esito dai log |
| --- | --- |
| Ripristino alle 14:11:49 | Connessione TLS ADB fallita in 5 ms. Ripristino interrotto prima di raggiungere il servizio dei permessi. |
| Riconnessione alle 14:12:20 | Connessione TLS riuscita in 74 ms. |
| Ripristino alle 14:12:27 | Prima apertura dello stream fallita dopo 10,002 s. Il canale shell si è aperto e chiuso durante il tentativo di lancio del servizio. Anche la seconda apertura dello stream è scaduta dopo 10,002 s. Ripristino fallito in **20,561 s**, senza risposta del servizio. |

Dopo l'ultimo tentativo i tre permessi Zepp e i relativi flag coincidevano con lo stato iniziale. La chiusura del comando shell non conferma l'avvio del servizio. Il log non mostra l'apertura del socket del servizio, quindi il prossimo punto da isolare è il suo avvio sullo Xiaomi.

Aggiornamento del dialogo: SyncBeat rilegge direttamente da Android i tre permessi Zepp all'apertura, dopo le azioni di gestione e al ritorno in primo piano. La lettura esplicita aggiorna il valore mostrato anche senza una sessione ADB attiva. Il numero di permessi concessi descrive lo stato attuale. La conferma in sospeso riguarda invece il ciclo precedente. I pulsanti di prova spiegano quale condizione manca quando l'operazione non può partire.

Con l'APK aggiornato, alle 14:21:23 la connessione TLS ADB è riuscita in **37 ms**. Fino all'ultima lettura osservata non risultavano nuove chiamate di ripristino o di sospensione. Tutti e tre i permessi Zepp risultavano concessi con i flag iniziali.

Su richiesta di Antonio, il codice è stato riportato a `914849f`, la versione precedente alle modifiche su riconciliazione, rilettura dei permessi e visibilità del dialogo. Le prove sopra restano documentate come storico.

| Percorso | Cosa valutare |
| --- | --- |
| ADB integrato con abbinamento da notifica | Elimina lo schermo diviso. Verificare se l'identità salvata resta autorizzata e se la porta di connessione viene ritrovata quando cambia. La build con la notifica rileva la porta di abbinamento; l'inserimento della porta di connessione rimane esplicito. Se Android spegne il debug wireless, serve riattivarlo. |
| Consegna del file al flusso musicale di Zepp | Potrebbe evitare del tutto la gestione dei permessi. Verificare se esiste un'interfaccia Android supportata che accetta direttamente il file. L'indagine precedente ha verificato l'apertura di Zepp; una consegna diretta resta da dimostrare. |
| Invio diretto con Zepp attiva | Eviterebbe la sospensione. I tentativi Classic osservati si sono fermati prima dell'autenticazione. Per rivalutare il percorso serve un trasferimento riproducibile con un riscontro sul funzionamento di Zepp durante l'invio. |
| Servizio autorizzato tramite USB, root o app aggiuntiva | Opzioni da considerare solo se cambiano i vincoli. Shizuku, usato dal solo telefono senza root, richiede a sua volta il debug wireless. |

### Prove di persistenza

Dopo un primo invio automatico riuscito e dopo aver verificato il ripristino, provare separatamente la chiusura e riapertura di SyncBeat, un cambio o una riconnessione Wi‑Fi e un riavvio del telefono. Per ogni caso annotare se il debug wireless è ancora attivo, se l'autorizzazione ADB è valida, se SyncBeat ritrova la connessione e quali azioni manuali servono. Verificare anche il comportamento con i soli dati mobili. Eseguire queste prove con invio e ripristino conclusi. Accettare un'alternativa come priva di passaggi ricorrenti solo per gli scenari riprodotti su hardware.
