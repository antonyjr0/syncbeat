# Progetto del prossimo incremento sul bootstrap

Progetto richiesto il 19 novembre 2026, successivo alla prova diagnostica delle 11:33. L'esito richiesto è una preparazione del servizio osservabile e conclusiva per ciascun gesto. Il progetto riguarda il servizio ADB e il suo collegamento locale, all'interno dei componenti esistenti. L'implementazione, le correzioni del lancio e le verifiche riuscite sono documentate nel [resoconto dello stesso giorno](zepp-bootstrap-resoconto-2026-11-19.md).

## Evidenze e obiettivo

La prova ha registrato un'apertura del socket rifiutata alle 11:33:40.706 e `SERVER_START` alle 11:33:40.819. Il listener viene costruito dopo questo log. L'attesa di 500 ms può quindi terminare prima che il servizio ascolti. Manca inoltre il segnale di avvio del primo processo lanciato durante la stessa prova, circostanza ancora da spiegare.

Nel pacchetto locale `flutter_adb` 1.0.0, `open()` aspetta `onWriteReady` fino a 10 secondi. La ricezione di `CLSE` chiude `onPayload`, ma lascia quell'attesa senza un esito immediato. La chiusura esplicita del peer e la mancata risposta confluiscono quindi nell'errore generico di apertura.

L'incremento deve produrre una sequenza verificabile di avvio, segnale `READY`, collegamento al socket e invio di `BEGIN`. In caso di errore la sequenza termina con una causa distinta. Il difetto iniziale di ripristino prematuro resta aperto e andrà rivalutato dopo aver superato questo blocco.

## Un tentativo per gesto

Un gesto può avviare un solo processo del servizio e aprire una sola volta il suo socket. L'apertura dello stream shell di lancio e l'apertura del socket sono due passaggi distinti della stessa preparazione. Ciascuno viene eseguito al massimo una volta.

La preparazione segue queste regole.

1. Con uno stream helper già aperto e valido si riusa quello stream.
2. In assenza dello stream si crea l'identità del tentativo e un endpoint locale nuovo, conforme al formato già accettato dal server. Si elimina l'apertura preventiva del socket usata oggi per scoprirne l'assenza.
3. Si lancia il servizio una volta, attraverso lo stream shell già previsto dall'app.
4. Si attende il segnale esplicito proveniente da quel lancio.
5. Dopo `READY` si apre il socket una volta. Solo il successo di questa apertura consente `BEGIN`.
6. Qualunque fallimento termina la preparazione. Un altro lancio o un'altra apertura richiede un nuovo gesto esplicito.

La scelta progettuale dell'endpoint nuovo per tentativo evita conflitti con un processo rimasto in ascolto dopo un errore precedente. Restano il socket astratto locale, il processo shell, il registro e il lock globale dei permessi già esistenti. Le credenziali ADB salvate mantengono la propria identità. Un vecchio processo conserva il watchdog, il recupero e la scadenza di inattività esistenti.

## Segnale di prontezza

Il servizio emette una sola riga `SYNCBEAT_READY_V1` sullo stdout del proprio lancio quando sono vere tutte le condizioni seguenti.

- Argomenti e UID sono stati validati.
- Il servizio ha costruito `LocalServerSocket` con successo.
- Il recupero iniziale è concluso e lo stato del registro è verificabile. Un recupero pendente produce un errore di preparazione e conserva le protezioni esistenti.
- Il servizio sta per entrare nel ciclo `accept()`.

`SERVER_START` continua a indicare l'inizio dell'avvio. Un nuovo evento `SERVER_READY` indica la prontezza effettiva.

Si propone di trasportare la riga sullo stream shell di bootstrap, mantenendo `nohup` e la separazione del processo dal client. Lo stdout rimane disponibile fino alla riga di prontezza, viene svuotato e poi chiuso dal servizio. Gli eventi successivi continuano a usare logcat. La chiusura dello stream shell segue il consumo del segnale. Un EOF prima della riga è un avvio fallito.

La tenuta di questo passaggio attraverso la shell Android è un requisito da verificare. Il test deve dimostrare che il segnale raggiunge Dart anche con avvio lento e che il servizio resta vivo dopo la chiusura dello stream di lancio. Se il test fallisce, si rivede il canale del segnale prima di procedere al ciclo dei permessi.

Il riconoscimento del segnale gestisce righe spezzate tra payload e l'arrivo immediato dei dati. Ogni attesa appartiene all'identità del proprio tentativo. Una risposta tardiva o ricevuta dopo annullamento perde efficacia e non può avviare `BEGIN`.

## Apertura dello stream ed errori

Si propone una funzione locale di apertura per i soli stream del bootstrap Zepp, usando le API pubbliche già presenti nel pacchetto fissato a 1.0.0. La funzione registra `AdbStream` nella connessione e installa gli osservatori prima di inviare `OPEN`. Conserva i payload arrivati prima della consegna dello stream al chiamante. Il parser ADB e il trasporto TLS restano quelli della dipendenza.

Questa soluzione circoscrive la gestione di `OKAY`, EOF e timeout al codice dell'integrazione Zepp nel repository. L'apertura osserva anche `onConnectionChanged`, prima dell'invio, per riconoscere la perdita del trasporto. Questo controllo è necessario perché `_sendRaw()` nella dipendenza intercetta alcuni errori di scrittura senza propagarli al chiamante. La cache globale dei pacchetti rimane una sorgente di sola lettura.

| Esito osservato | Classificazione | Comportamento |
| --- | --- | --- |
| `CLSE` prima del primo `OKAY` | Collegamento rifiutato | Errore immediato con fase e durata |
| Nessun `OKAY` o `CLSE` entro il limite di apertura | Timeout del collegamento | Errore alla scadenza |
| Stream shell aperto, nessun `READY` entro il limite di bootstrap | Timeout di prontezza | Tentativo concluso |
| EOF dello stream shell prima di `READY` | Avvio terminato prima della prontezza | Tentativo concluso |
| Errore del recupero iniziale del servizio | Recupero pendente | Preparazione bloccata e stato pendente conservato |
| TLS disconnesso o `Broken pipe` | Canale ADB interrotto | Tentativo concluso |
| Dati incompatibili con il segnale atteso | Risposta di prontezza non valida | Tentativo concluso |

Il primo evento terminale osservato chiude l'attesa una sola volta. La pulizia rimuove gli osservatori e la registrazione dello stream appartenenti al tentativo, chiude le risorse possedute e gestisce le risposte tardive. Un identificatore di stream ancora riconoscibile dal peer viene escluso dal riuso durante la stessa connessione.

I codici distinti devono attraversare anche `ZeppAdbCoordinator.call`, che oggi riduce gli errori a un booleano. Il messaggio dell'app deve rendere distinguibili rifiuto, timeout e perdita del canale. Nei log compaiono fase, codice, ID del tentativo e durata, con payload e credenziali esclusi.

## Limiti temporali e recupero

Il progetto riusa come limiti iniziali i 10 secondi di apertura e i 5 secondi già assegnati allo stream di bootstrap. I 5 secondi diventano il limite per ricevere `READY` dopo l'apertura dello stream shell. Il successo dipende dal segnale. L'attesa fissa di 500 ms viene rimossa.

Questi valori sono configurazioni esistenti da sottoporre alla verifica dell'incremento. I 113 ms osservati dimostrano la race di avvio e lasciano aperta la scelta di una durata adeguata su hardware. Il piano di implementazione dovrà controllare che le attese rientrino nel limite esterno di 75 secondi del coordinatore e che, alla scadenza locale, il tentativo sia effettivamente invalidato.

Il `finally` conserva il recupero dell'operazione, con queste precisazioni necessarie al vincolo di un tentativo per gesto.

- Se il bootstrap è fallito prima della scrittura di `BEGIN`, il `finally` registra che la preparazione è fallita e riporta l'eventuale recupero non verificabile. Riutilizza esclusivamente le risorse già disponibili. L'attuale secondo lancio automatico del servizio viene eliminato.
- Se `BEGIN` può essere stato scritto, il recupero prova `RESTORE` una volta sul canale disponibile e mantiene registro, watchdog, gestione di EOF e stato pendente.
- Il pulsante esplicito **Ripristina permessi Zepp** è un nuovo gesto e può preparare il servizio una volta per quell'azione.
- Un marker pendente preesistente conserva il proprio significato. Il fallimento del nuovo bootstrap non costituisce una prova di ripristino del ciclo precedente.

La distinzione tra recupero esplicito e recupero dal `finally` passa come informazione interna nelle chiamate già esistenti, evitando che entrambi invochino `_ensureHelper()` con facoltà di rilancio.

## Verifica prima dell'avanzamento

La verifica locale deve coprire il percorso normale dell'app e i seguenti casi.

| Caso | Esito richiesto |
| --- | --- |
| Prontezza oltre i vecchi 500 ms, entro il limite di bootstrap | Apertura unica del socket dopo `READY` |
| Segnale immediato o spezzato in più payload | Ricezione completa e conclusione unica |
| `CLSE` prima di `OKAY` | Rifiuto immediato, con contatori invariati dopo l'errore |
| Peer silenzioso | Timeout distinto dal rifiuto |
| EOF prima di `READY` | Avvio fallito e zero aperture del socket |
| Timeout seguito da `READY` o `OKAY` tardivo | Zero scritture tardive di `BEGIN` |
| Due chiamanti concorrenti nella stessa preparazione | Un solo lancio e una sola apertura condivisa |
| Fallimento del bootstrap seguito dal `finally` | Zero lanci e aperture aggiuntivi |
| Nuovo gesto dopo errore, con vecchio servizio ancora vivo | Endpoint nuovo e un tentativo per il nuovo gesto |
| `BEGIN` già scritto e perdita del canale | Conservazione del recupero e del registro pendente |

Si rieseguono inoltre i test esistenti su ordinamento `BEGIN` → `RESTORE`, risposta tardiva, lettura dello stato e ripristino dei permessi. Seguono formattazione dei file interessati, analisi Flutter, test pertinenti e compilazione Android.

La verifica sul telefono procede in due checkpoint.

1. Test di integrazione sul telefono della preparazione e del collegamento, con baseline dei permessi concessi e nessuna chiamata a `BEGIN`. Il test richiama lo stesso percorso di preparazione usato dall'app e termina dopo l'apertura. La diagnosi distingue il lancio, `READY`, l'unica apertura e il relativo esito. Si verifica che il servizio resti disponibile dopo la chiusura dello stream shell. Questo checkpoint viene eseguito dall'agente con log raccolti direttamente dal telefono.
2. Dopo il superamento del primo checkpoint, un solo gesto sul ciclo esistente **Prova sospensione e ripristino (senza file)**. L'agente raccoglie log e permessi durante il ciclo e legge il messaggio finale dall'accessibilità del telefono.

L'agente prepara e installa l'aggiornamento necessario ai checkpoint, secondo l'autorizzazione già data dall'utente nella sessione. Il resoconto deve riportare esito, ordine degli eventi, contatori dei tentativi e stato finale dei permessi. Un errore mantiene l'incremento aperto.

Solo dopo la verifica di questo incremento si rivaluta il difetto iniziale sul percorso di invio. Il protocollo musicale, i metadati, l'MTU, le sessioni multi-file, la discovery della porta e l'architettura restano fuori dal progetto richiesto.

Questo documento conserva il progetto approvato. Il resoconto collegato riporta lo stato effettivo dell'implementazione e delle verifiche.
