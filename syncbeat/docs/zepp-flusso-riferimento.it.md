# Flusso Zepp di riferimento (branch `experiment/zepp-flusso-riferimento`)

Data: 2026-11-17. Stato: bozza di confronto, non testata sull'orologio.

## Scopo

Un'implementazione **separata e parallela** del collegamento telefono → orologio
(Amazfit Active 3 Premium, firmware 6.6.14.5), costruita da zero sulle due fonti
pubbliche verificabili, per poterla confrontare riga per riga con
l'implementazione esistente:

- **Gadgetbridge** (codeberg.org/Freeyourgadget/Gadgetbridge) — riferimento del
  framing Classic BTBR e del trasferimento file V3.
- **OronBox** (github.com/zxor-org/OronBox, AGPL-3.0) — unica implementazione
  pubblica trovata che dichiara di aver caricato musica con successo su un
  Active 3 Premium reale.

Nessun file del flusso esistente (`zepp/`, `ZeppBridge.kt`, `zepp_client.dart`,
dialog) è stato modificato nel suo comportamento. Il codice nuovo vive in
posizioni separate (prefisso `Ref` / `zepp_ref`) ed è raggiungibile solo
attraverso i canali platform `syncbeat/zepp_ref*`, che nessuna schermata usa
per default.

## File aggiunti

| File | Contenuto |
|---|---|
| `android/app/src/main/java/com/example/syncbeat/zeppref/RefWire.java` | Framing BTBR `0x55 ... 0xaa`, CRC16/CCITT sull'header, CRC32 opzionale sul payload, AES-128-ECB |
| `.../zeppref/RefChunked.java` | Codec degli endpoint "chunked" (cap 20..512, flag 1/2/4/8, cifratura payload+seq+CRC32 con chiave XOR handle) |
| `.../zeppref/RefFlow.java` | Le 8 fasi del collegamento, con diagnostica in millisecondi per fase |
| `android/app/src/main/kotlin/com/example/syncbeat/RefBridge.kt` | Bridge MethodChannel/EventChannel, stessa API di `ZeppBridge` |
| `lib/features/zepp/zepp_ref_client.dart` | Client Dart, stessa API di `ZeppClient` |
| `android/app/src/test/java/com/example/syncbeat/zeppref/RefProtocolTest.java` | 6 test JVM, incluso un loopback completo contro un "orologio finto" con ECDH reale |

`MainActivity.kt` ha solo tre aggiunte: il campo `zeppRef`, la registrazione dei
canali `syncbeat/zepp_ref` e `syncbeat/zepp_ref/events`, e il fallback del
risultato dei permessi verso `zeppRef`.

## Le 8 fasi (RefFlow.run)

1. **Canali** — attesa dei canali di notifica (`MSG_BIG_BEGIN`) e invio abilitazione notifiche. Fonte: OronBox `zeppos_btbr_transport.dart`, `startConnection`/`beginMsgBig` (righe ~300-340).
2. **Sessione + MTU** — comando 3 (SESSION_START) con nonce casuale di 4 byte, risposta 4 con `[sessionId][mtu u16 LE]`, poi comando 17 per dichiarare il proprio MTU. Fonte: OronBox righe 308-337; Gadgetbridge `ZeppOsBtbrSupport.java` (`onMtuChanged`).
3. **Autenticazione ECDH** — sull'endpoint 0x1301/0x1381 (chunked, non cifrato): invio chiave pubblica (comando 3), ricezione chiave dell'orologio (comando 4), segreto condiviso via BouncyCastle B-163 (`ECDH_B163`, riusata dal pacchetto `zepp`), invio numero casuale cifrato AES (comando 5), ricezione numero cifrato (comando 6), attesa conferma 0x82 sul canale auth. Fonte: OronBox `zeppos_device_component.dart` (`performAuth`) e `zeppos_btbr_transport.dart` (`handleAuth`); Gadgetbridge `ZeppOsBtbrSupport.java` (`performAuth`).
4. **Servizi** — subscribe agli endpoint 0x0004 (ESTENSIONE) e 0x0013 (VERSIONE); risposta automatica alle richieste di capability dell'orologio (`C = 0x01/0x02 → risposta 0x05/0x06`). Fonte: OronBox `zeppos_btbr_transport.dart` (`beginServices`).
5. **Capacità (V3)** — query delle capability del trasferimento file sull'endpoint 0x0027: firmware V3, tipo, servizio, max 256 B. Fonte: Gadgetbridge `ZeppOsFileTransferV3.java` (`setHandleCapabilities`); OronBox `zeppos_v3_file_transfer.dart`.
6. **Richiesta di upload** — sull'endpoint 0x0027 (chunked, **cifrato** dalla fase 3 in poi): `0x12` + URL `music://0{escaped}` + timeout u32 + dimensione file u32. Attesa dell'accettazione `0x13` con byte di stato (0 = rifiutato, 1 = accettato). Fonte: OronBox `zeppos_music_upload_system.dart` (righe 197-220 per il payload) e `zeppos_v3_file_transfer.dart`; l'URL `music://` è identico al flusso esistente.
7. **Invio a blocchi** — sul canale 2 (`FILE_SEND`, endpoint 0x0020): header di 11 byte `[0x12][u32 size][u32 offset][u16 CRC16]`, blocchi di dimensione **pari al MTU di sessione negoziato** (come OronBox: `_write` frammenta a `maxWriteLength` = MTU di sessione, senza ulteriori limiti), poi attesa dell'ack `0x13` + offset u32 + CRC u16. Fonte: OronBox `zeppos_v3_file_transfer.dart` righe 84-95 e `zeppos_btbr_transport.dart` righe 75, 337.
8. **Chiusura** — scrittura finale, disconnessione ordinata. La fine della sessione (comando 6 con `[sessionId][0x03]`) azzera lo stato cifratura/MTU, come Gadgetbridge e OronBox.

Il ping di keep-alive (comando 19) riceve il pong (comando 20) con
`[session][1][0][0]` (OronBox riga 378) e viene ignorato a parte il reset del
timer di inattività. Gli ack del codec chunked `[4,0,handle,1,count]` seguono
OronBox `zeppos_device_component.dart` riga 184.

## Test automatici (JVM, senza orologio)

`RefProtocolTest.java`, 6 test, tutti verdi al 2026-11-17:

1. framing: writeFrame/readFrame round-trip, con e senza CRC32;
2. AES-128-ECB round-trip;
3. codec chunked: frammentazione a 512, riassemblaggio, ack;
4. codec chunked cifrato: payload+seq+CRC32 con chiave XOR handle;
5. ECDH B-163: segreto identico tra le due parti;
6. **loopback completo**: un "orologio finto" (thread separato, socket pair)
   esegue le fasi 1-7 come le implementano OronBox/GB; `RefFlow` completa
   sessione, autenticazione ECDH reale, negoziazione capacità, richiesta di
   upload cifrata e invio di un file da 1 MiB con ack per blocco.

Limite dichiarato: il test 6 verifica la coerenza interna del riferimento,
**non** che l'orologio reale si comporti così. Solo un test sul dispositivo di
Antonio può dirlo.

## Come confrontare con l'implementazione locale

Il dialog "Invia all'orologio" ha un interruttore **"Flusso di riferimento
(confronto)"** in cima: spento usa il flusso abituale (`ZeppClient`), acceso usa
il riferimento (`ZeppRefClient`). Le API sono identiche, quindi il confronto e'
solo la scelta del canale platform; il passaggio e' possibile solo a operazione
ferma e ricarica l'elenco dei dispositivi. Per un confronto riga per riga del
codice, i file `Ref*`/`zepp_ref*` restano affiancati a quelli esistenti.

Ogni fase logga i millisecondi impiegati, quindi un eventuale blocco sul
dispositivo si localizza sulla fase esatta invece che su un timeout generico.

## Limiti onesti

- **Non testato su hardware.** Antonio esegue il test sul suo orologio.
- OronBox dichiara il supporto dell'Active 3 Premium (BLE+BTBR), ma non ci sono
  prove pubbliche indipendenti del successo su questo firmware specifico.
- Nessuna promessa di compatibilità con altri modelli o firmware.
- L'obiettivo resta la **coesistenza con Zepp**: niente reset, unpair, kill di
  processi o ADB. Se il collegamento fallisce, il flusso si ferma e riporta la
  fase, senza riprovare da solo.
- La scelta "blocchi = MTU di sessione" nella fase 7 segue OronBox;
  Gadgetbridge frammenta diversamente (`calcMaxWriteChunk`, cap 512). Non è
  dimostrato quale delle due l'orologio preferisca: è uno dei punti da
  confrontare.
