# Musica sull'orologio Zepp, dentro SyncBeat

**Stato: sperimentale. Non provata su un orologio reale.** Il codice compila,
i test software passano, ma l'autenticazione, il servizio `music` e l'importazione
sul firmware dell'Amazfit Active 3 Premium non sono mai stati verificati.

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
2. In SyncBeat vai su **MP3 locali** e tocca l'icona orologio sul brano scelto.
   Per cominciare usa un file breve.
3. **1. Mostra dispositivi abbinati**. Concedi **Dispositivi nelle vicinanze**
   se Android lo chiede. L'app non cerca dispositivi e non usa la posizione.
4. Scegli il tuo orologio controllando nome e ultime cifre dell'indirizzo.
   Se non c'e', fermati: l'app non crea abbinamenti.
5. Inserisci la **chiave** (32 cifre esadecimali) nel campo mascherato. Non
   scriverla in chat, issue o screenshot. Il campo si svuota quando parte
   l'operazione e l'app non la salva su disco. Se non hai la chiave, puoi
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

- Solo Bluetooth Classic (RFCOMM) e file transfer V3 con servizio `music`.
- Massimo 32 MiB per brano; titolo e artista fino a 200 byte, senza `& ? # % =`.
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

## Aggiornamento 16/11/2026 (sera): connessione Classic allineata a OronBox

Errore osservato su "Verifica collegamento": `Reaf failed, socket might closed or timeout, ready ret: -1`, quasi immediato, prima dell'autenticazione. La causa non e' dimostrata. Cosa cambia in `ZeppBridge.kt`, confrontando con il profilo Zepp di OronBox (https://github.com/zxor-org/OronBox, `MainActivity.kt` e `device_profile.dart`):

- Stesso servizio di prima (UUID `00000022-0000-3512-2118-0009af100700`), nessun canale RFCOMM indovinato, nessun `removeBond`.
- Prima di connettersi si ferma una ricerca Bluetooth in corso (`cancelDiscovery`, come Gadgetbridge e OronBox). Serve il permesso `BLUETOOTH_SCAN` (solo Android 12+, "senza posizione"); se lo neghi si prosegue lo stesso.
- Per ogni pressione del pulsante: prima socket "insecure", poi, se fallisce, socket standard (ordine di OronBox; fin qui SyncBeat usava solo la standard). Dopo non ci sono altri tentativi automatici.
- Se fallisce, il messaggio indica fase e tipo di errore con i millisecondi (es. `insecure: IOException dopo 12 ms`), mai chiave o indirizzo.

Il codice e' scritto qui e usa solo API Android standard: da OronBox sono state prese l'ordine dei tentativi e l'UUID, non il testo del codice. OronBox e' AGPL-3.0 con termini aggiuntivi (obbligo di attribuzione se se ne distribuisce codice); chi la cita come origine non ne e' limitato. Non e' una garanzia che l'orologio risponda: si sa solo dopo il test.
