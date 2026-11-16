# Zepp — analisi dinamica passiva del trasferimento MP3

Sessione del **5 novembre 2026**, telefono Xiaomi Android 16/API 36,
Zepp `com.huami.watch.hmwatchmanager` **10.10.1-play**, versionCode 151992.
Orologio: Amazfit Active 3 Premium dichiarato dall'utente; firmware non rilevato.
Tutti gli orari della timeline sono **Europe/Rome, UTC+01:00**.

## Risultato

È verificato che Zepp usa `com.huami.watch.devicemusic.page.DeviceMusicManagerActivity`
e apre il selettore Android con `ACTION_OPEN_DOCUMENT`, categoria `OPENABLE`,
MIME `*/*`. È osservato il ritorno del risultato alla stessa Activity Zepp.
Non sono visibili il valore del risultato, l'URI selezionato o il suo contenuto.

È verificata una connessione **Bluetooth Classic RFCOMM attribuita a Zepp**,
già stabilita prima dell'apertura della pagina musicale, con numerosi eventi
di congestione/controllo di flusso durante la sessione. I campioni Wi-Fi indicano
Wi-Fi disabilitato. **Non è dimostrato che i byte dell'MP3 attraversino quel
canale RFCOMM**: la correlazione è compatibile con questa ipotesi, ma non basta
a escludere altri canali Bluetooth o a ricostruire il protocollo applicativo.

Classificazione conclusiva del **trasporto del file: E — non identificabile
con certezza dai dati disponibili**. Ipotesi più sostenuta: **B — Bluetooth
Classic**, confidenza media; confidenza alta sulla presenza della connessione
RFCOMM Zepp, distinta dalla confidenza sul trasporto del file.

Il completamento è stato **confermato dall'utente in chat**. Non è stata trovata
nei log una conferma applicativa univoca di completamento del trasferimento MP3.

## Metodo e raccolta

Script: `scripts/monitor-zepp-transfer.ps1`, PowerShell persistente nascosto,
con worker concorrenti e arresto tramite file locale. Nessun comando di
interazione con Zepp, Intent, `am start`, `input`, selezione file, grant, modifica
di impostazioni o connessioni. Nessuna acquisizione screenshot, video, HCI o
pcap; nessuna lettura di dati privati. Non è stato modificato SyncBeat.

Fonti raccolte:

- Logcat continuo, buffer `main`, `system`, `events`, `crash`, formato epoch;
  stream completo senza filtro di processo e stream separati ActivityManager/
  ActivityTaskManager, picker, Bluetooth e rete. Nessun buffer cancellato.
- `dumpsys activity activities`, ogni circa 2 secondi nel worker corretto;
- `dumpsys activity services com.huami.watch.hmwatchmanager`, circa 8 secondi;
- `dumpsys bluetooth_manager`, circa 10 secondi;
- `dumpsys connectivity`, `dumpsys wifi`, `ss -tun`, `ip -s link`, ciclo circa
  15 secondi più il tempo dei comandi;
- versione del dispositivo/app, riferimento dell'orologio del telefono e
  timestamp UTC host prima/dopo le interrogazioni. Non è stato impostato l'orologio.

Logcat usa il clock del dispositivo; gli snapshot sono delimitati da timestamp
host UTC. Il riferimento `date +%s` del telefono è in `device-info.txt` per
correlazione alla precisione del secondo; le latenze di interrogazione e il
campionamento impediscono attribuzioni temporali più precise agli snapshot.
I timestamp millisecondi Logcat non implicano sincronizzazione assoluta al
millisecondo con il PC.

I log non filtrati sono preservati. Gli indici `logcat-filtered.txt`,
`analysis-candidates.txt`, `recovered-candidates.txt` e `timeline-analysis.txt`
sono derivati successivamente e non sostituiscono gli originali.
[Riferimento ufficiale Logcat](https://developer.android.com/tools/logcat).

## Integrità e limiti della sessione

La navigazione dell'utente è iniziata prima dell'avvio dello stream continuo.
Il primo collector parte alle **10:00:45**, quando la pagina Musica è già aperta.
Gli eventi precedenti sono stati recuperati successivamente dal buffer Logcat
ancora disponibile tramite `logcat -d`, senza cancellarlo. Sono quindi evidenze
storiche del dispositivo, non eventi osservati in diretta dal collector.
Il buffer contiene anche attività precedenti e successive: nella timeline sono
selezionati soltanto gli eventi pertinenti, distinguendoli dal precedente test
Intent. In particolare, l'avvio tramite launcher qui riportato proviene da
`com.miui.home`, non dal test ADB precedente.

Nel primo collector un errore nella forma dell'array PowerShell ha reso
inutilizzabili inizialmente tre worker di snapshot (Activity, servizi e Bluetooth).
Il worker rete e lo stream Logcat completo hanno continuato a raccogliere.
Lo script è stato corretto e un secondo collector passivo è partito alle
**10:01:21**, lasciando il primo attivo per evitare buchi nel Logcat.
Gli snapshot affidabili di Activity/servizi/Bluetooth iniziano alle 10:01:22;
non vanno trattati come baseline precedente al trasferimento. I file temporanei
`*-current.stdout` del primo tentativo non sono evidenze affidabili.

Gli stream Logcat reindirizzati hanno mostrato buffering sul PC: i file sono
risultati pieni alla chiusura dei reader. La presenza dei processi era verificata
durante la raccolta; il contenuto effettivo è stato verificato dopo l'arresto.
La prima raccolta contiene **38.904 righe** di Logcat, circa 5,5 MB; la seconda
circa 1,6 MB, con sovrapposizione da non contare come eventi distinti.

Dopo il messaggio «trasferimento concluso» sono stati creati i file di arresto
locali. Entrambi i collector risultano `stopped`, senza worker/stream attivi,
alle **10:01:52–10:01:53**. È stato terminato esclusivamente il processo ADB
lettore di ciascuno stream, non Zepp o il server ADB. Il dump finito del buffer
eseguito dopo la richiesta di arresto è una lettura aggiuntiva delimitata, non
un monitoraggio rimasto attivo.

## Archivio locale

Tutto il materiale diagnostico resta sotto `tools/zepp-transfer/`:

- `20261105-100045-204/`: prima raccolta, rete, Logcat continuo e
  `logcat-buffer-recovery.txt` (buffer storico recuperato dopo il test);
- `20261105-100121-257/`: seconda raccolta con worker snapshot corretti;
- `latest-session.txt`: riferimento locale all'ultima sessione.

Ogni sessione contiene `logcat-raw.txt`, `activities.txt`, `services.txt`,
`bluetooth-events.txt`, `network-events.txt`, `device-info.txt`, `timeline.txt`,
file per gli stream specifici, diagnostica collector e stato finale.
Il buffer recuperato è UTF-16 prodotto da PowerShell; gli stream continui
sono letti come UTF-8. Nessun originale è stato convertito o sovrascritto.

La directory `tools/` era già esclusa da Git: verificato con `git check-ignore`
sui log effettivi. Nessun log grezzo, indirizzo, nome file, identificativo di
dispositivo/account o altro dato personale è incluso in questo report.
Nessun upload dei log, commit o push eseguito.

## Timeline ed evidenze

Abbreviazioni delle fonti, relative a `tools/zepp-transfer/`:

- **R**: `20261105-100045-204/logcat-buffer-recovery.txt`;
- **L**: `20261105-100045-204/logcat-raw.txt`;
- **N1**: `20261105-100045-204/network-events.txt`;
- **S2**: `20261105-100121-257/services.txt`;
- **A2**: `20261105-100121-257/activities.txt`;
- **T1/T2**: `timeline.txt` nelle rispettive sessioni.

| Evento | Ora locale | Fonte ed evidenza | Confidenza | Limite |
| --- | --- | --- | --- | --- |
| Connessione RFCOMM di Zepp | 09:59:13.505–09:59:14.259 | R righe 381074, 381391 e contesto: stack RFCOMM associa connessione all'UID Zepp, socket connesso su canale 25 | Alta sulla connessione | Precede il picker; non prova di trasferimento MP3 |
| Apertura Zepp da launcher utente | 10:00:06.834 | R riga 406448: `StartUpActivity`, chiamante launcher Xiaomi | Alta | Evento recuperato dal buffer storico |
| Home Zepp | 10:00:09.319 | R riga 408427: `MainTabActivity` avviata da Zepp | Alta | Non identifica il tab dispositivo selezionato |
| Pagina musicale | 10:00:17.403 | R riga 412018: avvio interno di `DeviceMusicManagerActivity` da Zepp | Alta sul componente | Nessuna acquisizione visiva del testo della pagina |
| Picker file Android | 10:00:20.738 | R riga 413295: `OPEN_DOCUMENT`, `OPENABLE`, `*/*`, chiamante Zepp, `PickActivity` | Alta | Extra presenti ma contenuto non esposto |
| Chiusura picker | 10:00:26.739 | R riga 420003: finish di `PickActivity` | Alta | Non indica da sola scelta valida o annullamento |
| Risultato e ritorno a Zepp | 10:00:26.772–26.786 | R riga 420289 e contesto: callback `ACTIVITY_RESULT`, resume della pagina musicale | Alta sul callback | resultCode, URI e nome file non disponibili |
| Stream continuo avviato | 10:00:45–46 | T1, timestamp di creazione stream e collector attivo | Alta | Il trasferimento era già in corso secondo contesto utente |
| Eventi RFCOMM ripetuti | 10:00:45.741–10:01:19.024 | L righe 5–27196: 472 eventi `rfcomm_cback` sul medesimo slot, in prevalenza `BTA_JV_RFCOMM_CONG_EVT` | Alta sugli eventi | Congestione/controllo di flusso non è una misura dei byte MP3 |
| Wi-Fi disabilitato nei campioni | 10:00:46.898, 10:01:02.978, 10:01:18.694, 10:01:34.613 | N1 righe 1075, 9072, 17068, 25069: stato Wi-Fi disabilitato | Alta sugli snapshot | Non prova assenza di ogni possibile modalità radio o evento tra campioni |
| Pagina e servizi Zepp presenti | da 10:01:22 | A2 e S2, primo snapshot delimitato | Alta sullo stato | Nessuna baseline valida dei servizi precedente al trasferimento |
| Completamento dichiarato | Messaggio utente «trasferimento concluso» | Chat, non Logcat | Dichiarazione esplicita dell'utente | Nessun timestamp interno di completamento ricostruibile |
| Raccolta arrestata | 10:01:52–53 | T1/T2 e `status.json` finali | Alta | Non è un evento di fine trasferimento Zepp |

La pressione del pulsante «Carica», la selezione del brano specifico, il punto
esatto di avvio invio, la percentuale MP3 e il messaggio finale non sono
direttamente identificabili. Esistono generici eventi touch e messaggi HTTP
`Progress ... 100%`: non permettono di attribuire un pulsante o il completamento
del file. Non sono usati come prove di questi eventi.

## Activity e file

Componenti effettivamente osservati nel flusso:

1. `com.xiaomi.hm.health.activity.StartUpActivity`;
2. `com.xiaomi.hm.health.activity.MainTabActivity`;
3. `com.huami.watch.devicemusic.page.DeviceMusicManagerActivity`;
4. package picker `com.google.android.documentsui`, Activity
   `com.android.documentsui.picker.PickActivity`.

Non è osservata un'Activity distinta per «sezione dispositivo» o «schermata
caricamento»: possono essere viste/fragment nella stessa Activity, ma questa
rimane un'ipotesi. La callback risultato conferma il percorso picker → Zepp,
non il valore del file restituito. Il contratto Android `OPEN_DOCUMENT` è
compatibile con un URI e una concessione SAF; il valore concreto, gli eventuali
flag e la persistenza del grant non sono visibili nei log raccolti.

## Servizi

Nei quattro snapshot S2 (10:01:22, 10:01:30, 10:01:38, 10:01:46) risultano
presenti, tra gli altri:

- `com.xiaomi.hm.health.device.service.HMCoreService`;
- `com.huami.watch.transport.DataTransportService`;
- `com.ingenic.iwds.uniconnect.ConnectionService`;
- `com.huami.watch.companion.otaphone.service.OtaService`;
- `com.huami.watch.companion.IME.IMEservice`;
- `com.huami.sky.ui.play.SkyPlayService`;
- `com.huami.watchfacesstore.task.InstallService`;
- servizio di notifica, invalidazione Room e processo sandbox Chromium.

La loro presenza è verificata; **non è verificato che siano stati attivati dal
trasferimento**, né che uno in particolare gestisca i byte audio. Non compare
una prova univoca di avvio di un servizio dedicato MP3 nel periodo acquisito.

## Bluetooth, Wi-Fi e rete

La catena UID Zepp → socket RFCOMM → slot usato negli eventi di congestione
è un'evidenza più specifica del semplice Bluetooth acceso. Conferma attività
su un canale Classic dell'app, ma tale connessione era già presente prima
della scelta del file. I dump Bluetooth contengono anche stato e cronologia di
altri client: non sono automaticamente attribuiti a Zepp o all'MP3.

Nessun log di avanzamento audio o conteggio di byte per file lega in modo
univoco quel canale al trasferimento. BLE resta non confermato/non escluso
come canale dati o controllo; non è provata una combinazione Bluetooth/Wi-Fi.

Wi-Fi disabilitato è campionato anche nella seconda raccolta, alle 10:01:22
e 10:01:38. Nei dati esaminati non emerge una nuova connessione Wi-Fi
attribuibile al file. La rete Internet del telefono e i socket IP visibili
non provano il trasporto verso l'orologio. `ss -tun` restituisce dati parziali
insieme a `Cannot open netlink socket: Permission denied`: nessun aggiramento
dei permessi è stato tentato. I contatori `ip -s link` non identificano il
payload né l'app proprietaria.

## Valutazione SyncBeat

L'analisi dinamica conferma la funzione della
`DeviceMusicManagerActivity`, che nell'inventario precedente risulta **non
esportata**, senza Intent Filter. Il suo avvio osservato è interno a Zepp:
non costituisce un'interfaccia richiamabile da SyncBeat.

Il ritorno SAF è collegato alla richiesta originata da Zepp; SyncBeat non può
semplicemente aprire il picker e consegnarne il risultato a un'altra Activity.
I servizi presenti e il socket RFCOMM non forniscono un contratto pubblico,
un formato dei messaggi o autorizzazione a controllare il trasferimento.

Rimane **C — verificato soltanto l'avvio normale di Zepp** per la precedente
valutazione Intent/IPC. Non emerge una nuova interfaccia verificata per aprire
Musica o passare il file. Un trasferimento diretto senza UI Zepp non è
dimostrato fattibile da questa osservazione; non è stata implementata alcuna
integrazione. Il flusso manuale già usato dall'utente conserva l'app Musica
originale dell'orologio; non è stata verificata la riproduzione sull'orologio.

## Prossimi esperimenti

1. Una futura sessione passiva avviata e verificata **prima** della navigazione
   darebbe una baseline completa dei servizi e delle connessioni, senza
   affidarsi al buffer storico. Nessuna nuova sessione è stata avviata dopo
   questa analisi.
2. Un confronto controllato tra idle e trasferimento di un MP3 sintetico noto
   potrebbe rafforzare l'attribuzione dei contatori, se disponibili per socket.
   La correlazione resterebbe distinta dalla decodifica del protocollo.
3. Per identificare il payload occorrerebbe una diagnostica Zepp documentata o,
   soltanto con **consenso separato**, una cattura Bluetooth HCI; una cattura
   rete richiederebbe anch'essa consenso separato. Anche tali acquisizioni
   potrebbero non rendere leggibile un protocollo cifrato/autenticato.
4. Chiedere a Zepp un contratto ufficiale di handoff MP3 rimane il percorso
   più diretto per una futura integrazione mantenendo il player originale.

## Uso e verifica del monitor

```powershell
# Avvio manuale; mantiene aperto il terminale oppure si avvia come processo nascosto.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/monitor-zepp-transfer.ps1

# Arresto sicuro, senza agire su Zepp o Bluetooth:
$session = Get-Content tools/zepp-transfer/latest-session.txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/monitor-zepp-transfer.ps1 -Mode Stop -SessionPath $session
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/monitor-zepp-transfer.ps1 -Mode Status -SessionPath $session
```

Alternativa semplice: creare `stop.request` nella cartella della sessione.
Con più sessioni attive arrestarle singolarmente. Nessun timeout automatico
interrompe un test; Ctrl+C nel terminale del collector passa dalla chiusura
dei propri reader. Per il processo nascosto usare il file/Mode Stop.

Verificati: parsing PowerShell senza errori, dati originali salvati, worker
corretti operativi, Stop tramite file, entrambe le sessioni `stopped`,
assenza dei processi collector dopo la chiusura, esclusione Git dei log.
La prima invocazione di Stop come script diretto era bloccata dalla execution
policy Windows: l'arresto è stato effettuato scrivendo il file locale previsto;
i comandi documentati usano la policy soltanto per il processo PowerShell.
Nessuna impostazione Android è stata modificata.

Controlli finali: `dart format .` (50 file, nessuna modifica), `flutter analyze`
(nessun problema), 2 test Python dell'inventario esistente superati,
`git diff --check` senza errori. Non sono state ripetute build o installazioni:
questa attività aggiunge solo il monitor PowerShell e questo report.
