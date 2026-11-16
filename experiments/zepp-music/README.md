# SyncBeat Zepp Lab

Prototipo Android separato per importare **un MP3 locale nel lettore Musica
originale dell'Active 3 Premium** tramite Bluetooth Classic/RFCOMM.

**Stato:** il percorso reale e' implementato e l'APK debug compila. I test
software passano. Non e' stato collegato l'orologio di Antonio: autenticazione,
servizio `music`, importazione e riproduzione su quel firmware restano da provare.

Non e' una simulazione spacciata per un trasferimento. L'app usa un vero socket
Bluetooth; il test automatico usa invece un dispositivo simulato e non prova
la compatibilita' hardware. Non c'e' una funzione Bluetooth nascosta
nell'app Flutter normale: per ora si installa questa piccola app separata.

## 1. Cosa ti serve

- Un PC con Android Studio e JDK 17. Non servono Flutter, Spotify, password
  Zepp o chiavi API per **compilare** questa app di prova.
- Android 8.0 o successivo per installarla.
- Un MP3 locale che hai diritto di trasferire. Per iniziare scegli un file
  breve, poi un normale brano se il primo funziona.
- Per la prova reale serve la chiave del tuo abbinamento con Zepp. Non
  scriverla in chat, nel repository, nel terminale o in una issue. Se non la
  possiedi, puoi compilare e leggere la schermata ma **fermati prima del collegamento**:
  il recupero sicuro della chiave e' una fase separata da concordare. Non viene
  chiesta o scaricata automaticamente da questa app.

## 2. Scaricare il branch e compilare

Dalla cartella del repository sul PC:

```sh
git fetch origin
git switch experiment/zepp-native-music
git pull --ff-only origin experiment/zepp-native-music
```

Se Git dice che hai modifiche locali, **non** usare reset/clean: salvale prima
con il tuo normale flusso. Non serve fare merge su main.

In Android Studio scegli **Open** e apri la cartella
`experiments/zepp-music`, non la cartella Flutter `syncbeat`.
Attendi il Gradle Sync. Se richiesto installa Android SDK Platform 35 e
Build Tools 35, e imposta **Gradle JDK = 17** nelle impostazioni di Gradle.
Poi scegli **Build > Build App Bundle(s) / APK(s) > Build APK(s)**
(il nome della voce puo' variare con la versione di Android Studio).

Da terminale, con JDK 17 e Android SDK gia' configurati, dalla stessa cartella:

```sh
./gradlew testDebugUnitTest assembleDebug lintDebug
```

Su Windows usa `gradlew.bat` al posto di `./gradlew`.
Il wrapper scarica Gradle e le dipendenze di compilazione. Nessun segreto serve.
L'APK prodotto e':

```text
experiments/zepp-music/app/build/outputs/apk/debug/app-debug.apk
```

Il suo nome sul telefono e' **SyncBeat Zepp Lab**, package
`com.antonyjr0.syncbeat.zeppprototype`. E' distinto da SyncBeat normale:
non devi disinstallare la tua app, non ne sostituisce il database o i download.
E' una build debug per prova locale, non una release firmata per lo store.

## 3. Prima prova, in ordine

Non abbiamo eseguito questi passi sul tuo hardware. Sono istruzioni per
una futura prova consapevole, non un invito a cambiare abbinamento alla cieca.

1. Apri Zepp e completa la sincronizzazione delle attivita'. Annota versione
   firmware dell'orologio e versione Android del telefono, senza dati privati.
2. Non rimuovere l'orologio da Zepp, non resettarlo e non cambiare regione.
   Due app possono contendere il collegamento. Per la prova evita che Zepp
   tenga attiva la connessione, senza disassociarlo. Se non sai come procedere,
   fermati: non disinstallare app o cancellare dati per tentativi.
3. Apri **SyncBeat Zepp Lab**. Scegli il tuo MP3 dal selettore file Android e
   scrivi titolo/artista. Limite del prototipo: 32 MiB, metadati fino a 200 byte;
   evita `& ? # % =` e caratteri di controllo. Non vengono modificati i tag del file.
4. Premi **Mostra dispositivi abbinati**. Concedi **Dispositivi nelle vicinanze**
   se Android lo chiede. L'app usa solo il permesso di collegamento Bluetooth:
   non cerca dispositivi nelle vicinanze e non richiede la posizione.
5. Scegli esplicitamente il tuo orologio nell'elenco, controllando nome e
   suffisso dell'indirizzo. Non scegliere una voce solo perche' e' la prima.
   Se non c'e' una voce gia' abbinata, fermati: il prototipo non crea abbinamenti.
   Se Android propone un nuovo abbinamento durante la prova, annulla e fermati.
6. Solo se possiedi gia' la chiave corretta, inseriscila **nel campo mascherato
   dell'app sul tuo telefono**. Non salvarla in screenshot o registrazioni.
   Il campo viene svuotato all'avvio della connessione; l'app non la salva su disco.
7. Premi **Verifica collegamento e servizio music** e controlla il dispositivo
   indicato nella conferma. Questa fase apre il collegamento, autentica e legge
   le capacita', ma **non invia il brano**. La presenza del solo Bluetooth non basta.
8. Solo se vedi **Autenticazione riuscita. Servizio music presente**, premi
   **Invia MP3 al lettore nativo**. Controlla titolo, artista e dimensione nella
   conferma. Questa azione scrive un brano sull'orologio. Non elimina altri brani.
9. Tieni l'app in primo piano e il telefono vicino all'orologio. Un blocco e'
   conteggiato solo dopo la sua conferma. Alla fine compare **Ultimo blocco confermato**:
   non significa che abbiamo verificato la libreria o ascoltato il file.
10. Apri il lettore **Musica originale sull'orologio**, cerca titolo/artista e
    riproduci davvero il brano. Annota il risultato senza chiavi o log grezzi.
11. L'app chiude il socket al termine. Riapri Zepp e controlla che si riconnetta
    e sincronizzi le attivita'. Non dichiarare riuscita la prova senza questo controllo.

Per un secondo brano si fa una nuova verifica esplicita. Non c'e' una coda
automatica e non viene tentata una ripresa non verificata dopo un'interruzione.
Un upload puo' lasciare un file parziale o duplicato: controlla l'orologio prima
di riprovare. Il prototipo non implementa cancellazione o rollback del brano;
usare soltanto i controlli gia' disponibili dell'orologio/Zepp.

## 4. Se qualcosa non va

| Messaggio / situazione | Significato e cosa fare |
| --- | --- |
| Permesso negato / Bluetooth spento | Nessun collegamento parte. Abilita solo il permesso Bluetooth necessario o attiva Bluetooth, poi premi di nuovo Mostra dispositivi. |
| Nessun dispositivo abbinato | L'app non esegue pairing. Non fare reset o unpair per tentare di risolvere. |
| Autenticazione rifiutata | Chiave non accettata o sessione occupata/incompatibile. Non incollare la chiave in un report. Fermati per capire la causa. |
| Il firmware non dichiara music | Il collegamento puo' funzionare ma l'importazione scelta non e' esposta. Non cerchiamo una cartella alternativa e non forziamo l'upload. |
| Solo file transfer V3 | Questa prima versione non implementa il trasferimento V1/V2. Non e' un errore del file MP3. |
| Conferma blocco errata / integrita' fallita | Trasferimento fermato, nessun successo annunciato. Controlla prima se sull'orologio c'e' un file parziale. |
| Ripresa non verificata | L'orologio segnala dati gia' presenti. Il prototipo non riparte da un offset senza una prova dedicata. |
| Tempo massimo superato | 30 secondi per leggere il file, 2 minuti per il collegamento/verifica, 5 minuti di attesa dopo la verifica e 10 minuti per l'upload. Nessun retry automatico. |
| Lasci la schermata, spegni lo schermo o premi Interrompi | Il socket viene chiuso. Potrebbe restare un file parziale. Per riprovare occorre una nuova verifica. |
| Ultimo blocco confermato, ma brano assente o non riproducibile | Il test NON e' riuscito. Segnala la differenza senza forzare reset o altri trasferimenti. |

Tornare a `main` sul PC:

```sh
git switch main
```

Rimuovere **solo SyncBeat Zepp Lab** dal telefono non cambia i dati della normale
SyncBeat. Non rimuove eventuali file gia' scritti sull'orologio.

## 5. Limiti e verifiche

- Solo Bluetooth Classic/RFCOMM e file transfer V3 con capacita' `music` dichiarata.
  Non esiste fallback BLE o Wi-Fi nascosto.
- Non modifica firmware, regione, pairing, allarmi o attivita' dell'orologio.
- Nessun accesso Internet nell'APK, nessuna telemetria, nessun log di chiavi o frame.
  La chiave e le chiavi di sessione restano in memoria per la sessione e vengono
  eliminate per quanto possibile alla chiusura; questo non e' una garanzia di
  azzeramento forense di tutte le copie interne del sistema Java/Android.
- Lo screenshot viene bloccato prima dell'inserimento della chiave e resta bloccato
  per il resto di quella schermata. Non registrare il contenuto con altri mezzi.
- I test automatici verificano protocollo/framing, cifratura e casi di errore con
  dati sintetici. La UI viene renderizzata con Android/Robolectric, non col tuo telefono.
  Non sono una misura di velocita', stabilita' radio o consumo energetico reali.
- I vecchi commenti del 2025 sui 2 MB non sono un limite certo attuale. Questo
  prototipo non dimostra che i problemi siano risolti. La documentazione upstream
  continua a segnalare instabilita' BLE; Classic e' un percorso da provare.

Dettagli tecnici: [ARCHITECTURE.md](ARCHITECTURE.md).
Licenze e file adattati: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
La versione che incorpora codice Gadgetbridge e' AGPL-3.0-or-later; il testo MIT
originale resta conservato. Nessun cambiamento e' stato fatto a `main`.

Esito dei controlli: [VALIDATION.md](VALIDATION.md).
[Anteprima delle schermate, senza chiavi o dati personali](docs/ui-preview-390.png).
