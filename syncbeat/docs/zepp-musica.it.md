# Musica sull'orologio Zepp, dentro SyncBeat

**Stato: sperimentale, trasferimento non ancora riuscito su hardware reale.**
Il 17 novembre 2026 la prova su Active 3 Premium ha superato collegamento,
autenticazione e controllo del servizio `music` dopo aver tolto temporaneamente
a Zepp il permesso Dispositivi nelle vicinanze. L'importazione si ferma alla
risposta iniziale, prima dei blocchi audio. Il vecchio messaggio accorpava rifiuto,
sessione inattesa e risposta incompleta: la diagnostica ora distingue i tre casi
e mostra il codice numerico di un eventuale rifiuto. La prova della versione
diagnostica sul dispositivo ha restituito stato `5`, con sessione corretta e
nessun blocco audio inviato. Il codice sorgente upstream consultato tratta ogni
stato diverso da zero come rifiuto, senza documentare il significato di `5`:
non attribuirlo a memoria piena, formato o autorizzazioni senza altre prove.
La guida ufficiale Amazfit include Active 3 Premium e descrive l'importazione
da Zepp con connessione Wi-Fi: https://www.amazfit.jp/blogs/upyourgame/music1 .
La prova con Zepp 10.10.5-play ha importato lo stesso MP3; l'utente ha confermato
la riproduzione nel lettore dell'orologio. Durante la prova Android riportava
Wi-Fi disattivato, nessuna route WLAN, e un socket Classic di Zepp connesso al
canale 25. Non assumere quindi che questo firmware richieda il Wi-Fi: il problema
rimane nel percorso SyncBeat. L'analisi locale dell'APK installato mostra che
Zepp limita titolo e artista a 31 byte nel percorso musicale e sostituisce
l'artista assente con uno spazio. SyncBeat invece propone il basename completo
del download e permetteva 200 byte. Il codice ora propone un titolo entro 31 byte
senza spezzare caratteri UTF-8, applica il limite anche nel nativo e usa uno spazio
per l'artista assente. I test software passano; il nuovo comportamento non e'
ancora verificato sull'orologio e non risolve da solo la contesa con Zepp.

Questa e' una funzione della **stessa app Flutter SyncBeat**. Non c'e' nessuna
seconda app da installare. Una piccola parte e' scritta in Kotlin/Java dentro
`syncbeat/android/` perche' il Bluetooth Classic su Android si puo' usare solo
da codice nativo; l'interfaccia e' Flutter.

## Cosa fa

Nell'elenco **MP3 locali** (quello gia' usato per ascoltare i brani scaricati)
compare, accanto a ogni brano, un'icona **orologio**. Apre una finestra
**Invia all'orologio**, senza pagine nuove: scegli l'orologio tra i
dispositivi gia' abbinati, inserisci la chiave di abbinamento Zepp, controlli
titolo e artista, e l'app invia **un** MP3 al lettore Musica originale
dell'orologio via Bluetooth Classic.

I download (Jamendo, YouTube, MP3 locali) e i file in `Download/SyncBeat` non
vengono toccati: l'app legge soltanto il file scelto.

## Come scaricare il branch

Dalla cartella del repository (quella che contiene `.git`):

```sh
git fetch origin
git switch --track origin/experiment/zepp-native-music
```

Se Git risponde che il branch locale `experiment/zepp-native-music` esiste gia'
(per esempio perche' l'hai creato con `git checkout -b`), rinominalo: non perdi
niente.

```sh
git branch -m experiment/zepp-native-music zepp-locale-vecchio
git fetch origin
git switch --track origin/experiment/zepp-native-music
```

Se hai modifiche non salvate, fermati prima: non usare `reset` o `clean`.
`main` non cambia. Per tornarci: `git switch main`.

## Come compilare (Flutter)

Il progetto Flutter e' nella cartella **`syncbeat/`** dentro il repository
(quella con `pubspec.yaml`). Tutti i comandi si danno da li':

```sh
cd syncbeat
flutter pub get
flutter run            # telefono Android collegato con debug USB
# oppure, per generare l'APK:
flutter build apk --debug
```

L'APK esce in `syncbeat/build/app/outputs/flutter-apk/app-debug.apk`.
Servono Flutter (versione stabile recente) e Android SDK con JDK 17, come per
il resto del progetto. Non serve altro.

## Prima prova, in ordine

1. Apri Zepp e completa la sincronizzazione. Non rimuovere l'orologio, non
   fare reset, non cambiare regione. Due app possono contendersi il
   collegamento: se non sai come lasciarlo libero, fermati.
2. In SyncBeat vai su **MP3 locali**, tocca l'icona orologio sul brano scelto e
   seleziona **Invio diretto da SyncBeat (sperimentale)**.
   Per cominciare usa un file breve.
3. **1. Mostra dispositivi abbinati**. Concedi **Dispositivi nelle vicinanze**
   se Android lo chiede. L'app non cerca dispositivi e non usa la posizione.
4. Scegli il tuo orologio controllando nome e ultime cifre dell'indirizzo.
   Se non c'e', fermati: l'app non crea abbinamenti.
5. Inserisci la **chiave** (32 cifre esadecimali) nel campo mascherato. Non
   scriverla in chat, issue o screenshot. Il campo si svuota quando parte
   l'operazione. Al primo uso viene conservata nell'archivio sicuro Android,
   associata al singolo orologio, e riutilizzata senza mostrarla nel campo.
   **Dimentica chiave salvata** la cancella; per sostituirla inseriscine una nuova.
   Se non hai la chiave, puoi
   leggere la finestra ma **fermati qui**: il recupero sicuro della chiave e' una
   fase separata, non automatica.
6. **3. Verifica collegamento (non invia)**: si connette, autentica e legge le
   capacita'. Non manda musica.
7. Solo se vedi *Autenticazione riuscita e servizio music presente*, premi
   **4. Invia MP3**. Controlla la conferma: scrive un brano sull'orologio e non
   cancella altro. Tieni l'app aperta e il telefono vicino all'orologio.
8. A fine invio compare *Ultimo blocco confermato*. Non significa che il brano
   funzioni: apri il lettore **Musica** dell'orologio e riproducilo davvero.
   Poi riapri Zepp e controlla che si riconnetta e sincronizzi.

Ogni invio e' una nuova connessione: un solo brano alla volta, nessuna coda,
nessun nuovo tentativo automatico dopo un errore.

## Se qualcosa non va

Una prova reale del 17 novembre 2026 ha raggiunto `connect()` ma ha ricevuto
`read failed, socket might closed or timeout, read ret: -1` dopo 483 ms.
Il fallimento precede l'autenticazione e il trasferimento: non dimostra una
chiave errata o un problema dell'MP3. Android elenca il dispositivo come DUAL
e ha in cache il servizio `00000022`; questo non garantisce che il servizio sia
disponibile in quel momento. Zepp era in esecuzione. La prova successiva consiste
nel completare la sincronizzazione, arrestare temporaneamente Zepp e ripetere
una sola verifica senza inviare file, quindi riaprire Zepp. Esito ancora da
verificare; nessun reset o nuovo abbinamento richiesto.

| Messaggio | Cosa fare |
| --- | --- |
| Permesso Bluetooth negato / Bluetooth spento | Attivalo dalle impostazioni Android e premi di nuovo il pulsante 1. |
| Nessun dispositivo abbinato | Niente reset o unpair. Abbinalo prima da Android/Zepp nel modo normale. |
| Autenticazione rifiutata | Chiave sbagliata o collegamento occupato da Zepp. Non incollare la chiave in un report. |
| Il firmware non dichiara music | L'orologio non espone l'importazione scelta. L'app non forza l'invio. |
| Solo file transfer V3 | Questa prima versione non supporta le versioni V1/V2. Non e' un problema del file. |
| Conferma blocco errata | Invio fermato. Controlla se sull'orologio e' rimasto un file parziale prima di riprovare. |
| Tempo massimo superato | 2 minuti per la verifica, 12 per un invio. Nessun tentativo automatico. |
| *Ultimo blocco confermato* ma brano assente | La prova **non** e' riuscita. Segnalalo senza altri trasferimenti. |

Il brano importato non si cancella da SyncBeat: usa i controlli dell'orologio
o di Zepp. Se interrompi l'invio puo' restare un file parziale.

## Limiti

### Ricerca della connessione parallela

Il requisito e' completare l'invio in SyncBeat mantenendo Zepp operativa, senza
revocare permessi o fermarla. Non considerare il passaggio manuale a Zepp una
soluzione equivalente. Il coordinator Active 3 Premium di Gadgetbridge dichiara
`ConnectionType.BOTH`: e' un'indicazione dei trasporti implementati, non prova
di sessioni simultanee. Per verificarne le capacita', la finestra offre
**Verifica connessione parallela (senza invio)**. Apre BLE sul dispositivo gia'
abbinato per massimo 20 secondi, legge i servizi e verifica le caratteristiche
`16`, `17`, `23` della famiglia UUID Zepp. Non scrive caratteristiche o descrittori,
non abilita notifiche, non autentica e non invia MP3. Chiude il proprio GATT su
esito, errore, annullamento o timeout; non modifica i permessi di altre app.
Una risposta positiva richiede ancora di verificare che Zepp resti connessa e
non dimostra che l'autenticazione o l'invio musicale possano convivere.

La prova reale ha registrato il client GATT con successo, ma non ha ricevuto
`STATE_CONNECTED` nei 20 secondi: nessuna lettura dei servizi e' iniziata.
Il timeout ha cancellato l'apertura e chiuso il client; non e' stato inviato
alcun comando di autenticazione o blocco audio. Il risultato non dimostra
l'assenza di BLE sul dispositivo, ma non offre una soluzione parallela verificata.

### Percorso tramite Zepp (ripiego esplicito)

L'utente ha accettato il passaggio a Zepp come ripiego, preferendo comunque
l'invio diretto in SyncBeat. L'icona orologio della libreria apre ora una finestra
con il nome del file, la cartella Download/SyncBeat, **Copia nome del file** e
**Apri Zepp per trasferire**. Il comando nativo usa esclusivamente il launcher
pubblico del package, con package visibility mirata. Non passa URI a componenti
interni, non apre socket, non cambia permessi e non conferma il trasferimento.
La selezione in Musica resta manuale. I file legacy privati non sono presentati
come selezionabili da Zepp: vanno prima esportati. Il percorso diretto precedente
e' ancora raggiungibile con un pulsante esplicitamente sperimentale.

### Client ADB Flutter integrato (percorso corrente)

La dipendenza pubblicata `flutter_adb: 1.0.0` gestisce ADB, TLS e pairing SPAKE2;
SyncBeat non ne ricopia il protocollo. Le dipendenze e il provider Shizuku sono
stati rimossi. Il collegamento e' limitato a `127.0.0.1`, non accetta host remoti
e richiede Android 11+ con Debug wireless attivo. La schermata **Configura debug
wireless (senza app aggiuntive)** apre **Debug wireless** con **Abbina dalla
notifica**. Se Android mostra le Opzioni sviluppatore, apri **Debug wireless**
da lì. Consenti le notifiche e scegli **Accoppia dispositivo
con codice di accoppiamento** e lascia il codice visibile. Quando SyncBeat trova
la porta di abbinamento del telefono, apri la tendina, scegli **Inserisci
codice** nella notifica **Abbina SyncBeat** e invia le sei cifre. Dopo
l'abbinamento, inserisci in SyncBeat la porta indicata nella pagina principale
di Debug wireless e premi **Collega**.
Il codice temporaneo non viene conservato; l'identita' RSA viene salvata tramite
`flutter_secure_storage` e riusata. Il logging dettagliato del pacchetto e' spento.

Il recupero nativo viene avviato tramite il collegamento ADB autorizzato come
processo shell separato. Espone solo BEGIN, PING e RESTORE su un socket locale
con nome casuale, verificando l'UID shell/root del peer. Non offre comandi shell
arbitrari all'interfaccia dell'app. Ogni risposta riporta l'identificatore della
richiesta, per non accettare risposte tardive per una richiesta diversa.
Una connessione persa o 15 secondi senza richieste chiudono la sessione e
tentano il ripristino; restano watchdog, registro atomico e ritentativi del
servizio gia' testato. Flutter invia heartbeat durante l'operazione e segnala
la perdita del servizio al nativo, che chiude il socket musicale.
Prima di installare la build si verificano software e rollback del servizio;
pairing TLS e invio reale con il pacchetto richiedono ancora la prova sul telefono.

Prova reale del nuovo trasporto locale: tramite ADB autorizzato e forwarding
temporaneo al socket del servizio, BEGIN ha sospeso il gruppo e la disconnessione
improvvisa del client ha ripristinato automaticamente lo stato originale di tutti
e tre i permessi. Nessun audio e' stato inviato. L'esito conferma il recupero del
servizio locale, non ancora il pairing TLS del pacchetto Flutter.
Una seconda istanza e' stata avviata durante la sospensione: non ha potuto
iniziare un'altra operazione ne' ripristinare quella attiva, anche chiudendo il
proprio client. Un file lock separa le transazioni fra processi; il registro
di recupero resta condiviso per il recupero dopo la chiusura del processo.

### Implementazione precedente con Shizuku (sostituita)

**Gestisci automaticamente Zepp** usa Shizuku API/provider 13.1.5 (MIT).
Richiede Shizuku installato, avviato e autorizzato per SyncBeat; niente root.
Sul telefono Xiaomi e' necessario anche **Debug USB (Impostazioni di sicurezza)**.
Shizuku deve essere riavviato dopo un riavvio Android. Il normale flusso resta
disponibile senza questa modalita'; nessun permesso di Zepp viene cambiato
finche' l'utente non la attiva e avvia una verifica, un invio o il test dedicato.

Il servizio shell agisce soltanto su `com.huami.watch.hmwatchmanager`, profilo
Android principale (utente 0), per `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` e
`BLUETOOTH_ADVERTISE`: sono i permessi dichiarati da Zepp nel gruppo
**Dispositivi nelle vicinanze** sul telefono verificato. Conserva gli stati
originali in un registro atomico privato alla shell prima di modificarli.
Non concede permessi che erano inizialmente negati.

La convalida locale di dispositivo, chiave, metadati e MP3 precede la sospensione.
Il ripristino e' nel `finally` nativo, dopo la chiusura del socket e prima della
risposta finale a Flutter, anche su errore file, rifiuto del firmware e annullamento.
Se il ripristino fallisce, l'esito non viene riportato come completato: il registro
resta disponibile e l'interfaccia offre **Ripristina permessi Zepp**.
Il servizio indipendente rileva la morte del processo client e ha un watchdog
(durata massima della verifica/invio piu' un minuto); i ripristini falliti vengono
ritentati ogni 10 secondi finche' il servizio e' vivo. Timer di una vecchia
operazione non possono ripristinare sopra un'operazione nuova.
Se viene terminato anche il servizio privilegiato o si riavvia il telefono, il
registro consente il recupero alla successiva attivazione di Shizuku e SyncBeat:
non e' garantito un ripristino immediato senza un servizio autorizzato in esecuzione.
Ripristinare il permesso non e' una prova che Zepp si sia gia' riconnessa.

**Prova sospensione e ripristino (senza file)** verifica il ciclo prima di un invio.
Il 17 novembre 2026 sono passati 31 test JVM (protocollo piu' transazione permessi)
e 7 test Flutter della finestra. Una prova shell del servizio reale sul telefono,
senza installare Shizuku o trasferire musica, ha confermato il ripristino di tutti
e tre i permessi dopo un errore simulato e dopo il timeout del watchdog.
Il percorso completo con autorizzazione Shizuku e invio reale resta da verificare.

Fonti: https://github.com/RikkaApps/Shizuku-API e
https://shizuku.rikka.app/guide/setup/ .

### Invio Classic esistente

- Solo Bluetooth Classic (RFCOMM) e file transfer V3 con servizio `music`.
- Massimo 32 MiB per brano; titolo e artista fino a 31 byte UTF-8, senza `& ? # % =`.
- Android soltanto (su Windows l'icona non compare).
- Nessun dato esce dal telefono per questa funzione. Nessun log di chiavi o dati.
- La chiave passa in memoria dal campo di testo al codice nativo e viene azzerata
  dove possibile; non e' una garanzia di azzeramento di ogni copia interna.
- La schermata e' protetta da screenshot e registrazione mentre e' aperta.
- I test usano un orologio simulato: provano protocollo, errori e interfaccia,
  non compatibilita' radio, velocita' o batteria reali.

## Licenza

Il protocollo e' adattato da Gadgetbridge (AGPL-3.0-or-later); per questo la
parte Zepp di SyncBeat e' **AGPL-3.0-or-later**. Il testo MIT originale resta in
`LICENSE-MIT`. Testi e avvisi sono nell'app (pulsante **Licenze** nella finestra
**Invia all'orologio**) e in `syncbeat/android/app/src/main/assets/licenses/zepp/`.

## Dov'e' il codice

- Interfaccia Flutter (finestra aperta da MP3 locali): `syncbeat/lib/features/zepp/`, collegata in `lib/features/audio_sources/local_audio_library.dart`
- Ponte Android: `syncbeat/android/app/src/main/kotlin/com/example/syncbeat/ZeppBridge.kt`
- Protocollo: `syncbeat/android/app/src/main/java/com/example/syncbeat/zepp/`
- Test: `syncbeat/test/zepp_transfer_test.dart`, `syncbeat/android/app/src/test/java/`

Il vecchio prototipo separato in `experiments/zepp-music/` resta nella storia
del branch solo come riferimento. **Non serve compilarlo.**

## Aggiornamento 16/11/2026 (sera): connessione Classic, confronto con OronBox

Errore osservato su "Verifica collegamento": `Reaf failed, socket might closed or timeout, ready ret: -1`, quasi immediato, prima dell'autenticazione. La causa non e' dimostrata. Cosa cambia in `ZeppBridge.kt`, confrontando con il profilo Zepp di OronBox (https://github.com/zxor-org/OronBox, `MainActivity.kt` e `device_profile.dart`):

- Stesso servizio di prima (UUID `00000022-0000-3512-2118-0009af100700`), nessun canale RFCOMM indovinato, nessun `removeBond`.
- Prima di connettersi si ferma una ricerca Bluetooth in corso (`cancelDiscovery`, come Gadgetbridge e OronBox). Serve il permesso `BLUETOOTH_SCAN` (solo Android 12+, "senza posizione"); se lo neghi si prosegue lo stesso.
- Resta un solo tentativo per pressione, con la socket standard come prima (stessa scelta di Gadgetbridge). OronBox prova prima una socket "insecure": non l'ho adottata, e' una scelta aperta da decidere con un test, non in automatico.
- Se fallisce, il messaggio indica fase e tipo di errore con i millisecondi (es. `IOException dopo 12 ms`), mai chiave o indirizzo.

Il codice e' scritto qui e usa solo API Android standard: da OronBox e' stato preso solo il confronto (UUID, cancelDiscovery), non il testo del codice. OronBox e' AGPL-3.0 con termini aggiuntivi (obbligo di attribuzione se se ne distribuisce codice); chi la cita come origine non ne e' limitato. Non e' una garanzia che l'orologio risponda: si sa solo dopo il test.

## Canale locale senza Wi-Fi, checkpoint B1 del 20/11/2026

Nel dialogo esistente **Invia all'orologio** sono disponibili **Prepara canale senza Wi-Fi (solo stato)** e **Verifica canale locale (solo stato)**. Questa versione del canale espone la lettura dello stato del servizio. L'integrazione dei comandi di sospensione, ripristino e invio offline segue i checkpoint successivi del piano.

Con Wi-Fi e Debug wireless autorizzato, il primo pulsante avvia il servizio e apre una connessione autenticata su `127.0.0.1`. La porta locale viene assegnata dal sistema e comunicata nel bootstrap. Le letture successive usano direttamente quella connessione, anche quando ADB risulta scollegato. Il secondo pulsante esegue una singola lettura di stato. Un errore termina quella richiesta e viene mostrato nel dialogo.

La sessione usa una credenziale casuale da 256 bit, inviata soltanto dopo che il processo ha confermato il proprio stdin con echo disabilitato. La credenziale rimane in memoria. Dopo l'autenticazione il listener chiude l'accesso a nuove connessioni e resta associato al solo collegamento autenticato. Il processo di prova termina quando quel collegamento viene chiuso. La terminazione di SyncBeat o dell'helper richiede una nuova preparazione con Wi-Fi e Debug wireless. Questo vale anche dopo il riavvio del telefono. La permanenza della sessione con schermo spento su HyperOS è da verificare.

Il bootstrap B1 riusa il collegamento ADB autorizzato corrente. Con l’incremento A2 del 23 novembre, se serve un nuovo collegamento la porta viene cercata tramite NSD, come descritto nella sezione seguente. Un errore richiede una nuova azione esplicita o una nuova apertura dell’app. Le conferme e l’attivazione del debug richieste da Android seguono le impostazioni di sistema.

La prova reale B1 va concordata prima dell'installazione. Prevede preparazione con Wi-Fi, spegnimento temporaneo del Wi-Fi e una lettura di stato dal canale locale, con confronto dei permessi Zepp prima e dopo. Lo stato delle prove è riportato nella sezione **Modifiche apportate, 20 novembre 2026** del [resoconto](zepp-bootstrap-resoconto-2026-11-19.md).

Il 23 novembre 2026 il checkpoint B1 è riuscito sul telefono HyperOS: lo stesso servizio ha risposto con Wi-Fi e Debug wireless spenti, senza nuovi bootstrap e con permessi Zepp invariati. La verifica riguarda il solo stato, con app in primo piano. Sospensione, ripristino e invio senza Wi-Fi restano ai checkpoint successivi; dettagli ed evidenze nella sezione del 23 novembre del resoconto.

## Download con invio esplicito e preparazione all’apertura, 23 novembre 2026

Il download da solo non invia musica. Dopo il salvataggio nel popup YouTube o Jamendo/MP3 locale, premi **Invia all’orologio** per un singolo invio al dispositivo configurato. Preparazione, avanzamento ed esito compaiono nello stesso popup. Il file usato è quello restituito dal salvataggio, anche quando Android restituisce un URI `content://`.

All’avvio di SyncBeat su Android, e quando la riapri dopo averla lasciata in background, l’app cerca il servizio di connessione Debug wireless di questo telefono tramite Android NSD. Individua la porta corrente, effettua un solo collegamento autenticato e prepara il canale locale B1 senza inviare musica né sospendere permessi. Se il collegamento è già pronto lo riusa. La schermata iniziale mostra preparazione, disponibilità o errore. Non ci sono riconnessioni periodiche dopo un errore.

La ricerca usa soltanto `_adb-tls-connect._tcp`, distinto dal servizio di pairing. Un candidato deve avere un nome ADB valido e risolversi a un indirizzo locale assegnato a questo telefono; la connessione usa comunque `127.0.0.1`. Se i candidati sono assenti o ambigui, l’app si ferma. La porta salvata non viene provata come secondo tentativo. La ricerca osserva i servizi per 5 secondi, con un limite complessivo nativo di 10 secondi, da verificare nelle condizioni reali della rete.

La prima volta Android richiede Debug wireless attivo e l’autorizzazione/abbinamento di SyncBeat. Dopo l’abbinamento dalla notifica, l’app individua la porta di connessione e prepara il canale automaticamente. **Collega automaticamente** consente un nuovo tentativo esplicito. Il campo per la porta manuale compare soltanto dopo un errore. Android può richiedere di riattivare Debug wireless dopo un riavvio o quando cambia la rete: l’app non può promettere che resti abilitato per sempre.

Se manca la configurazione dell’orologio, alla pressione di **Invia all’orologio** compare **Configura invio all’orologio**: scegli il dispositivo e usa la chiave già salvata oppure inseriscila. **Salva e continua** memorizza la scelta e prosegue l’invio richiesto. La configurazione da sola non sospende permessi e non invia musica. Le conferme di sistema di Android restano necessarie.

Un errore di invio lascia il file salvato e mostra **Invia all’orologio** per un nuovo tentativo esplicito, senza riscaricare il file. Non partono tentativi automatici aggiuntivi né invii in coda. Un ripristino Zepp pendente blocca il nuovo invio e mostra le indicazioni di recupero. Chiudere il popup o annullare l’operazione interrompe l’invio usando il percorso di annullamento e ripristino esistente.

Questo incremento usa ancora il flusso di sospensione e ripristino tramite Wi-Fi/ADB. Il canale locale B1 continua a esporre soltanto lo stato: l’invio senza Wi-Fi resta da implementare e verificare nei checkpoint successivi. **MP3 locali** conserva il percorso manuale già esistente. Le autorizzazioni al download e all’uso offline delle fonti mantengono le verifiche precedenti.
