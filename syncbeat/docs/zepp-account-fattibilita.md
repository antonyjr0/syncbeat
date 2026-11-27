# Recupero chiave dall’account Zepp — 24–25 novembre 2026

## Stato corrente: correzione del logout, 25 novembre

L’utente ha verificato che la prima implementazione lo ha scollegato dall’app
Zepp. Il precedente esito di recupero chiave rimane valido per la sola chiave;
la compatibilità con la sessione ufficiale è invece fallita. I paragrafi del 24
novembre sotto riportano la prova storica, non una garanzia di coesistenza.

Il client ora usa **l’accesso web** (`com.huami.webapp`, `device_model=web`,
`appplatform=web` e ID `web_...`) e **non chiama il logout remoto**. Le richieste
di autenticazione non ripiegano mai sull’identità mobile. Si chiude soltanto il
client HTTP locale, scartando password e token senza persisterli. L’eventuale
sessione server non viene revocata esplicitamente: chiudere HTTP non equivale a
fare logout. Non sono state cambiate la selezione MAC o la conservazione della
sola chiave nell’archivio sicuro.

La fonte del percorso web è il progetto dreeve-zepp-connector (AGPL-3.0), che
documenta lo stesso logout causato dal login mobile e una prova di coesistenza
con l’accesso web. È evidenza per la scelta tecnica, non una prova sul telefono
di questo utente:

- https://github.com/dreeveapp/dreeve-zepp-connector/blob/main/src/dreeve_zepp_connector/zepp_client.py
- https://github.com/dreeveapp/dreeve-zepp-connector/blob/main/CLAUDE.md

Il nuovo scambio ha quattro richieste esplicite, ciascuna limitata a 12 secondi
e 1 MiB, senza retry o redirect seguiti: registrazione web su `api-user.huami.com`,
login web, ottenimento app-token web e lettura dispositivi su `api-mifit.zepp.com`.
Tutte usano HTTPS. Il vecchio involucro AES e la dipendenza diretta da
PointyCastle sono stati rimossi (la dipendenza transitiva ADB resta invariata).
Le licenze e l’attribuzione sono incluse nell’APK.

Per convalidare la correzione, l’utente deve prima avere una sessione Zepp
funzionante, poi eseguire una volta il recupero web nella nuova build e verificare
che Zepp resti autenticata e sincronizzi. Il precedente checkpoint non copre
questo nuovo scambio. Non eseguire accessi o logout al posto dell’utente e non
leggere credenziali da altre app.

La diagnostica ADB è stata inoltre separata in rifiuto TCP, timeout, errore di rete
e autenticazione ADB/TLS non confermata, sopprimendo la stampa grezza della
dipendenza. Rimane una singola connessione: nessun probe, retry o reset delle
chiavi. Non è ancora una correzione della causa del problema sul telefono.
Il dispositivo rilevato oggi da ADB è M2006C3LVG, diverso dallo Xiaomi 15T della
prova precedente: è stata chiesta conferma del dispositivo di verifica.

Verifiche locali del nuovo incremento: **218 test Flutter superati** e analisi
statica senza segnalazioni. Il login web è stato poi verificato sul telefono,
compresa la permanenza della sessione Zepp (checkpoint del 25 novembre sotto).
Il guasto ADB è stato classificato come connessione rifiutata; la sua causa resta
da risolvere.
APK release correttivo compilato (177,2 MB), disponibile in
`build/app/outputs/flutter-apk/app-release.apk`. Inizialmente non installato,
in attesa del dispositivo corretto; è stato poi installato sullo Xiaomi 15T
dopo la conferma dell’utente (checkpoint qui sotto). Non sono stati eseguiti
accessi Zepp, modifiche ai permessi o tentativi di connessione sul telefono
diverso inizialmente rilevato da ADB.

### Installazione sul dispositivo corretto e avvio automatico riuscito

L’utente ha chiarito che il M2006C3LVG non era il suo telefono e ha chiesto di
riprovare. ADB ha rilevato nuovamente lo Xiaomi 15T (`goya_eea`): il nuovo APK
è stato installato con `adb install -r`, esito `Success`, e l’app è stata aperta.
Prima dell’avvio il flag `adb_wifi_enabled` era **0** e il privilegio
`WRITE_SECURE_SETTINGS` era già concesso. Non è stato ripetuto alcun grant.

Nel processo app PID 11589, in un solo avvio:

- `ADB_WIFI_ENABLE_REQUESTED` (wallMs 1795602704321);
- tre servizi NSD rilevati e un solo candidato locale selezionato;
- `ADB_AUTO_CONNECTED` (1795602709466);
- `DIRECT_BOOTSTRAP_READY`, chiusura della shell e `DIRECT_STATUS_OK` dal
  servizio PID 24568;
- `APP_PREPARATION_READY` (1795602709903).

Tempo complessivo circa **5,58 secondi**. La lettura indipendente del flag ha
confermato il passaggio **0 → 1**. Questo checkpoint prova attivazione automatica,
ricerca della porta, connessione ADB/TLS e preparazione del canale di sola lettura
sul telefono corretto. Il precedente errore non è stato riprodotto e la sua
causa non è stata dimostrata: il nuovo adattatore distingue gli errori, ma non
introduce retry o una modifica del trasporto che possa essere dichiarata come
correzione già provata di quel difetto.

Per il percorso account web è stata chiesta una prova separata: partire da Zepp
autenticata, recuperare la chiave nella nuova build e riaprire Zepp per verificare
che la sincronizzazione riesca senza nuovo login. La conferma è riportata sotto.

### Recupero web e permanenza della sessione confermati, 25 novembre

L’utente ha segnalato il pulsante account disabilitato. Dalla schermata aperta
si è verificato che l’elenco Bluetooth era caricato, ma il campo **Orologio** non
aveva una selezione: il pulsante richiede un dispositivo scelto. È stata aperta
la tendina e selezionata l’unica voce corrispondente ad Active 3. Nessun invio,
reset o modifica di chiave è stato effettuato da questi tocchi.

L’utente ha poi eseguito il recupero web. Nel processo PID 11589:
`ACCOUNT_RECOVERY_START` (1795603937754), `ACCOUNT_TOKENS_OK`,
`ACCOUNT_WEB_LOGIN_OK`, `ACCOUNT_KEY_MATCHED`, `ACCOUNT_KEY_MATCHES_SAVED`,
`ACCOUNT_KEY_SAVED` (1795603938319), circa **0,57 secondi** complessivi.
Non compare una chiamata di logout nel nuovo percorso. Il confronto della chiave
è booleano ed è avvenuto nell’app, senza esporne il valore.

Alla richiesta di riaprire Zepp e sincronizzare, l’utente ha confermato:
**«Sì, sincronizza senza nuovo accesso»**. Il checkpoint del recupero web con
sessione Zepp conservata è quindi riuscito su questo account e orologio.

Durante altre riaperture dello stesso processo il difetto ADB è stato invece
riprodotto più volte: un unico candidato selezionato, poi `ADB_CONNECT_REFUSED`
e `APP_PREPARATION_ERROR`, sia dopo richiesta di attivazione sia con flag già 1.
È un rifiuto della connessione TCP prima dell’autenticazione, non un esito che
dimostri l’assenza di privilegio o la necessità di rifare il pairing. La prima
apertura riuscita descritta sopra non chiude questo difetto. La discovery del
PC mostra più pubblicazioni del telefono con porte distinte: una pubblicazione
obsoleta è un’ipotesi da verificare, non una causa già provata. Non sono state
aggiunte scansioni di porte, connessioni di prova o tentativi automatici.

## Fattibilità e limiti

Il recupero è tecnicamente implementabile senza root, app aggiuntive o accesso
al database privato di Zepp. Il progetto MIT huami-token documenta nel codice
un accesso email/password e una lettura dei dispositivi associati. AmazToken
implementa lo stesso scambio su Android. Non si tratta di un’API pubblica
garantita da Zepp: cambiamenti dei server, account social, CAPTCHA, regioni
diverse e chiavi mancanti possono impedirne il funzionamento.

Riferimenti consultati:

- https://gadgetbridge.org/basics/pairing/huami-xiaomi-server/
- https://github.com/argrento/huami-token/blob/master/huami_token/zepp.py
- https://github.com/argrento/huami-token/blob/master/huami_token/constants.py
- https://github.com/argrento/huami-token/blob/master/huami_token/models.py
- https://github.com/LiveByTheCode/amaztoken
- https://docs.zepp.com/docs/guides/faq/third-party-login/

La documentazione ufficiale Zepp descrive, per chi usa un accesso social,
l’associazione di un’email allo stesso account e l’impostazione della password
tramite **Password dimenticata**. È un’operazione dell’utente in Zepp, non una
conversione automatica eseguita da SyncBeat, e non richiede di creare un altro
account o dissociare l’orologio. Non eseguire logout o cambi di credenziali al
posto dell’utente durante la verifica.

## Prima implementazione del 24 novembre (sostituita dal percorso web)

Nella configurazione, anche quella aperta dal download, scegli l’orologio già
abbinato e premi **Collega account Zepp**, poi inserisci email/password Zepp e
premi **Recupera chiave**. Il testo spiega destinazione delle credenziali e
conservazione della sola chiave. Il campo manuale resta disponibile.

La richiesta usa i tre host Zepp fissi della procedura di riferimento tramite
HTTPS, senza seguire redirect, retry o proxy applicativi. Legge localmente
il redirect dei token, apre una sessione temporanea e richiede l’elenco dei
dispositivi. Non legge musica, attività o altri dati sanitari e non cambia
abbinamenti, permessi Android o protocollo musicale. Il logout usa esclusivamente
il `login_token` della nuova sessione e viene tentato in finally; un errore di rete può impedirne
la conferma. Password e token non vengono salvati e non sono registrati nei log.
Il materiale AES/CBC fisso è parte del protocollo di riferimento e non una
credenziale dell’utente: la protezione del trasporto dipende da HTTPS.

La diagnostica registra solo fasi fisse `ACCOUNT_*`: avvio, token ottenuti,
login riuscito, corrispondenza della chiave, salvataggio, timeout o errore e
logout confermato/non confermato. Se esiste una chiave valida già salvata,
registra soltanto se coincide con quella restituita, senza valori o indirizzi.

La chiave è importata solo se un unico elemento corrisponde all’intero indirizzo
Bluetooth selezionato e contiene un `auth_key` esadecimale valido di 16 byte.
Non si deduce la corrispondenza dal nome, non si ripiega su `btKey` e non si
modifica la chiave salvata quando il recupero fallisce. Solo la chiave scelta
viene conservata nello storage sicuro già usato dall’app. Nessun invio parte.
Ogni richiesta ha limite di 12 secondi e risposta massima di 1 MiB; massimo
quattro richieste (token, login, dispositivi, logout), senza ritentativi.
Le schermate sono aperte all’interno della configurazione già protetta da
screenshot. Le stringhe Dart in memoria non offrono azzeramento garantito.

## Criteri di verifica sul telefono

I test locali simulano HTTPS con risposte sintetiche, inclusi errori e mancata
corrispondenza. Non dimostrano che il server accetti questo account o restituisca
la chiave del modello in uso. Serve un accesso eseguito dall’utente nella nuova
schermata; non chiedere credenziali in chat e non estrarle da altre app.
Prima confrontare privatamente la chiave importata con quella già funzionante,
registrando soltanto l’esito booleano, oppure verificare il collegamento senza
file. Controllare anche che Zepp continui a comunicare con l’orologio dopo
accesso e logout. Non dichiarare supporto generale o recupero confermato prima di questa prova.

Verifiche locali completate: **214 test Flutter e 56 test JVM superati**, analisi statica senza
segnalazioni e APK release compilato. Il vettore AES/CBC è stato confrontato con un risultato indipendente
generato tramite .NET usando dati sintetici. I test verificano corrispondenza MAC,
ambiguità, chiavi mancanti/non valide, redirect rifiutati, timeout, limiti di
risposta, logout dopo errore e importazione dal dialogo senza invio o concessioni.

## Installazione sul telefono

APK installato con aggiornamento in loco (`adb install -r`, `Success`). Il
privilegio `WRITE_SECURE_SETTINGS` risulta ancora concesso. L’app è stata aperta,
senza inviare musica e senza eseguire richieste all’account Zepp. L’utente non
ricorda al momento il metodo di accesso: il checkpoint con credenziali reali resta
pendente e non è stato sostituito da un test simulato dichiarato come reale.

Nell’avvio della nuova build, PID 28583, si è osservato un problema nel percorso
ADB preesistente: `ADB_WIFI_ENABLE_REQUESTED`, tre servizi NSD rilevati, un solo
candidato locale e `ADB_DISCOVERY_SELECTED`, seguito da `ADB_AUTO_CONNECT_ERROR`
e `APP_PREPARATION_ERROR`. Il flag Debug wireless risultava poi 1. L’errore
avviene nella connessione successiva alla selezione, non nella ricerca della
porta; i soli codici raccolti non distinguono ancora rifiuto del socket da errore
TLS. Nessun retry automatico è stato introdotto. Questo collegamento non è usato
dal recupero account HTTPS, ma resta da rivalutare prima della verifica senza
file e di nuovi invii. I permessi Bluetooth Zepp risultavano tutti concessi prima
dell’installazione. Il tentativo di aprire la configurazione tramite un tocco ADB
non ha cambiato schermata; non si dichiara quindi verificata sul dispositivo
l’apertura del nuovo dialogo account. La copertura del dialogo è per ora widget.

## Recupero reale riuscito — 24 novembre 2026

Successivamente l’utente ha eseguito il recupero dal telefono e ha comunicato
**fatto**. Nel processo PID 30294 sono state lette esclusivamente le fasi fisse:

- `ACCOUNT_RECOVERY_START` → `ACCOUNT_TOKENS_OK` → `ACCOUNT_LOGIN_OK`;
- `ACCOUNT_KEY_MATCHED` → `ACCOUNT_LOGOUT_OK`;
- `ACCOUNT_KEY_MATCHES_SAVED` → `ACCOUNT_KEY_SAVED`.

Il flusso è durato circa **5,14 secondi** dall’avvio al salvataggio. La chiave
restituita per l’indirizzo scelto coincide con la chiave valida già conservata
e usata negli invii precedenti. Il confronto è stato eseguito nell’app; nessun
valore è stato letto, mostrato o registrato dall’agente. Il logout della sessione
temporanea risulta confermato e il salvataggio nello storage sicuro è riuscito.
È quindi verificato il recupero reale su questo account e su questo orologio,
inclusa l’interfaccia usata dall’utente. Non è una garanzia per altri account,
modelli o modalità di accesso.

La precedente nota di verifica pendente descriveva lo stato al momento
dell’installazione ed è superata da questo esito. È stato chiesto all’utente
di controllare anche connessione e sincronizzazione in Zepp; la conferma di
questo controllo resta pendente. Nessun invio è stato avviato dall’agente.

Nella stessa apertura, prima del recupero account, ricompaiono
`ADB_WIFI_ALREADY_ENABLED`, `ADB_AUTO_CONNECT_ERROR` e `APP_PREPARATION_ERROR`.
Il successo HTTPS non risolve né convalida il collegamento ADB: il suo errore
rimane un problema distinto da diagnosticare prima dei successivi checkpoint.

## Aggiornamento del 25 novembre 2026

Il recupero precedente tramite login mobile e logout temporaneo è stato
sostituito dal percorso web per evitare l’invalidazione dell’accesso di Zepp.
L’utente ha ripetuto il recupero e ha confermato: **«Sì, sincronizza senza nuovo
accesso»**. I marcatori `ACCOUNT_WEB_LOGIN_OK`, `ACCOUNT_KEY_MATCHED` e
`ACCOUNT_KEY_SAVED` confermano il recupero e il salvataggio; non sono stati
letti o registrati i valori delle credenziali. Questo esito supera la verifica
pendente sul mantenimento della sessione riportata nella sezione precedente.

Il nuovo abbinamento ADB ha poi ripristinato l’autenticazione TLS. Il distinto
problema alla riapertura dopo cambio della porta è stato successivamente
ricondotto a un socket mDNS ereditato dal servizio locale di SyncBeat che
tratteneva la pubblicazione precedente. Il bootstrap ora chiude quella copia;
la release installata ha superato avvii con debug acceso o spento e tre
riaperture con cambio di porta. Il filtro mantiene il blocco su servizi ambigui.
Questa correzione non cambia il percorso account: i dettagli e i limiti delle
prove sono nel resoconto bootstrap del 25 novembre.
