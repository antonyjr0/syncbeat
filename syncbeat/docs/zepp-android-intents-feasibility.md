# Zepp Android — fattibilità Intent e IPC

Data: 5 novembre 2026. **Esito: C — possibile soltanto aprire Zepp**, nel
perimetro delle interfacce identificate e delle prove eseguite. Non è stata
identificata un'interfaccia verificata per aprire il caricamento MP3 o consegnargli
un file. Questo non dimostra l'assenza assoluta di qualsiasi route interna.

Confidenza **alta** sui componenti del manifest e sull'avvio launcher;
**media** sulla conclusione complessiva, perché i dispatcher generici e i
servizi esportati non espongono nel manifest il loro contratto applicativo.
Non è stata eseguita una prova da una seconda app Android con UID ordinario.

## 1. Ambiente e perimetro

| Voce | Valore verificato |
| --- | --- |
| Host | Windows, PowerShell, repository Flutter SyncBeat |
| Telefono | modello Android `25069PTEBG`, dispositivo `goya` |
| Sistema | Android 16, API 36 |
| Package ricavato dal dispositivo | `com.huami.watch.hmwatchmanager` |
| Etichetta APK confermata con aapt2 | `Zepp` |
| Versione | `10.10.1-play`, versionCode `151992` |
| SDK Zepp | minSdk 32, targetSdk 36, compileSdk 36 |
| Installazione | `base.apk` + `split_config.arm64_v8a.apk` |
| Strumenti | ADB SDK platform-tools, AAPT2 Build Tools 36.0.0, Python 3 standard library |
| Orologio | Amazfit Active 3 Premium, indicato dall'utente; firmware non rilevato |

Il package non è stato assunto da conoscenze precedenti: è stato trovato
nell'elenco delle app del telefono, poi verificato tramite etichetta e versione
dell'APK installato. L'analisi riguarda esclusivamente manifest e metadati del
Package Manager. Nessuna decompilazione del codice, lettura di dati privati,
root, modifica di Zepp o automazione di interazioni protette.

Le osservazioni dell'utente su selettore file, schermo acceso e trasferimento
senza configurazione Wi-Fi manuale costituiscono il contesto, non prove di un
protocollo o di un'API. Il trasporto effettivo non è stato indagato.

## 2. Integrazione SyncBeat esistente

- `android/app/src/main/kotlin/com/example/syncbeat/MainActivity.kt` registra
  `syncbeat/public_audio`, `syncbeat/youtube` e `syncbeat/youtube/events`.
- `PublicAudioBridge.kt` gestisce pubblicazione, validazione, verifica, apertura
  e indice persistente degli MP3. Su API 29+ inserisce in
  `MediaStore.Downloads.EXTERNAL_CONTENT_URI`, MIME `audio/mpeg`,
  `RELATIVE_PATH=Download/SyncBeat/`, inizialmente `IS_PENDING=1`.
  Dopo copia, verifica e salvataggio del record imposta `IS_PENDING=0`.
- Il risultato è un URI `content://`, conservato insieme al manifest audio;
  `lib/features/audio_sources/public_audio_storage.dart` è il punto Flutter
  che lo riceve e conserva. Per le versioni precedenti usa SAF e la scelta
  esplicita della cartella Download.
- L'azione nativa `open` già usa `ACTION_VIEW`, `audio/mpeg` e
  `FLAG_GRANT_READ_URI_PERMISSION`. `openFolder` apre i Download, non Zepp.
- Il manifest SyncBeat non dichiara una query per Zepp. Non è stato modificato.

Se in futuro esistesse un contratto pubblico verificato, il punto di aggancio
sarebbe un bridge Android separato che riceve l'URI già pubblicato, senza
interferire con OAuth, ricerca, matching, conversione, storage o player.
In questa sessione non sono stati modificati codice applicativo, UI, manifest
Android o dipendenze di SyncBeat.

## 3. Procedura ripetibile Windows

Prerequisiti: USB debugging autorizzato, Android SDK platform-tools e Build
Tools, Python 3.9+. Dalla cartella `syncbeat`:

```powershell
# Prima enumerare il dispositivo: non assumere il package.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/inspect-zepp-intents.ps1

# Dopo aver individuato il candidato sul telefono di questa sessione:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/inspect-zepp-intents.ps1 -PackageName com.huami.watch.hmwatchmanager
```

Con più dispositivi aggiungere `-Serial SERIAL`; con SDK non standard usare
`-SdkRoot 'C:\percorso\Android\sdk'`. Lo script si arresta se il telefono
non è autorizzato o la scelta del dispositivo è ambigua. Lo script non avvia
Zepp e non invia file. Confermare sempre `application-label:'Zepp'` nel file
`base-badging.txt` prima di attribuire l'inventario a Zepp.

Output in `tools/zepp-intents/<timestamp>/`, già escluso da Git:

- ambiente, `package.txt`, percorsi APK e risoluzione launcher;
- tutti gli APK installati, manifest leggibile AAPT2 e badging di ciascuno;
- inventario JSON completo di Activity, Alias, Service, Receiver e Provider,
  con exported esplicito o predefinito, permission, attributi, action,
  categorie, URI/MIME, autorità e permessi dei Provider;
- query di risoluzione MP3 (`send-mp3.txt`, `send-multiple-mp3.txt`, `view-mp3.txt`).

La raccolta completa è stata eseguita con successo in
`tools/zepp-intents/20261105-091159-792/`. Le prime letture e la prova launcher
sono in `tools/zepp-intents/`. Gli APK sono copie locali di sola lettura;
non vanno aggiunti al repository o redistribuiti.

Comandi ADB/AAPT2 effettivamente usati (seriale selezionato automaticamente
nello script, omesso qui):

```powershell
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
$aapt = "$env:LOCALAPPDATA\Android\sdk\build-tools\36.0.0\aapt2.exe"
$pkg = 'com.huami.watch.hmwatchmanager' # Verificato, non un valore universale.
& $adb devices -l
& $adb shell pm list packages -3
& $adb shell getprop ro.build.version.release
& $adb shell getprop ro.build.version.sdk
& $adb shell dumpsys package $pkg
& $adb shell pm path $pkg
# Lo script esegue adb pull sui percorsi restituiti, inclusi gli split.
# Per ciascun APK locale:
& $aapt dump badging 'tools/zepp-intents/base.apk'
& $aapt dump xmltree 'tools/zepp-intents/base.apk' --file AndroidManifest.xml
& $adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $pkg
& $adb shell cmd package query-activities --brief -a android.intent.action.SEND -t audio/mpeg -p $pkg
& $adb shell cmd package query-activities --brief -a android.intent.action.SEND_MULTIPLE -t audio/mpeg -p $pkg
& $adb shell cmd package query-activities --brief -a android.intent.action.VIEW -c android.intent.category.DEFAULT -d content://media/external/downloads/1 -t audio/mpeg -p $pkg
```

L'URI `/1` è sintetico e usato **solo per la risoluzione**: nessun file è stato
letto, concesso o inviato. Un esito negativo di queste query riguarda questi
Intent, non esclude ogni possibile contratto esplicito.

## 4. Componenti identificati

L'APK base dichiara 802 componenti: 698 Activity, 1 Activity Alias, 52 Service,
33 Receiver, 18 ContentProvider. Esportati: 30 Activity, nessun Alias, 22 Service,
11 Receiver e 1 Provider. Lo split ABI non dichiara componenti applicativi.
L'inventario JSON contiene i dettagli di tutti i componenti, non solo quelli
selezionati sotto. L'applicazione non dichiara una permission globale.

Classificazione delle interfacce, distinta dall'esito finale A–E:

- **A:** interfaccia pubblica documentata;
- **B:** componente esportato/route dichiarata, contratto Zepp non documentato;
- **C:** componente interno o protetto non disponibile a una normale app;
- **D:** relazione funzionale ipotizzata, non verificata.

### Activity candidate per musica e file

Tutte le Activity interne di questa tabella non hanno permission esplicita,
action, categorie, scheme o MIME dichiarati. `exported` è **assente**, non
letteralmente `false`: il valore effettivo è falso perché non hanno Intent
Filter. Non sono state invocate, neppure per provocare una SecurityException.
I nomi suggeriscono una funzione; non provano quale schermata usi questo modello
di orologio.

| Nome completo | Tipo | Exported effettivo | Classe / evidenza |
| --- | --- | --- | --- |
| `com.huami.watch.musicupload.DeviceMusicActivity` | Activity | false | C; nome specifico musicupload, relazione a questo orologio non verificata |
| `com.huami.watch.devicemusic.page.DeviceMusicManagerActivity` | Activity | false | C; gestione musica dispositivo per nome |
| `com.xiaomi.hm.health.device.MusicManagerActivity` | Activity | false | C; gestione musica per nome |
| `com.xiaomi.hm.health.device.HmEarbudMusicActivity` | Activity | false | C; riferimento a earbud, non prova di upload orologio |
| `com.huami.watch.wififtp.FileManagerActivity` | Activity | false | C; file manager per nome, non prova del trasporto usato |
| `com.huami.discovery.bridge.react.HMReactActivity` | Activity | false | C; contenitore generico, nessun contratto MP3 dichiarato |
| `com.huami.web.container.WebActivity` | Activity | false | C; contenitore web generico |
| `com.xiaomi.hm.health.discovery.WebActivity` | Activity Alias | false | C; target `com.huami.web.container.WebActivity`, nessun filtro |

Anche le cinque Activity `com.huami.sky.ui.intro.preference.SkyMusicPreferenceActivity`,
`com.huami.sky.ui.intro.preference.SkyMusicPreferenceEditActivity`,
`com.huami.sky.ui.realtime.SkyMusicListActivity`,
`com.huami.sky.ui.setting.SkyMusicVolumeControlActivity` e
`com.huami.sky.ui.play.ui.SkyMusicControlActivity` non sono esportate, non hanno
filtri e non sono state testate. Non costituiscono un ingresso esterno.

### Componenti esportati o altri candidati

| Nome completo | Tipo / exported | Permission | Action e categorie | URI / MIME | Valutazione |
| --- | --- | --- | --- | --- | --- |
| `com.xiaomi.hm.health.activity.StartUpActivity` | Activity / true esplicito | nessuna | `MAIN` + `LAUNCHER`; ulteriori filtri sotto | varie route sotto; nessun MP3 | A per il launcher Android, B per le route Zepp; avvio ADB riuscito, nessuna prova di upload |
| `com.xiaomi.hm.health.device.earbud.service.EarbudMusicDownloadService` | Service / true esplicito | `android.permission.BIND_JOB_SERVICE` | nessuna | nessuno | C: servizio riservato al sistema; il nome earbud non dimostra relazione all'orologio |
| `com.xiaomi.hm.health.device.service.HMCoreService` | Service / true esplicito | nessuna nel manifest | `android.intent.action.HMCoreService`, `.SYNC_DATA`, `.START_FOREGROUND`, `.STOP_FOREGROUND`, `.KEEP_ALIVE` (stesso prefisso); nessuna categoria | nessuno | B; nessun contratto audio dimostrato; non avviato |
| `com.xiaomi.hm.health.opensdk.HMOpenService` | Service / true esplicito | nessuna nel manifest | nessuna | nessuno | B; nome opensdk, ma nessun contratto MP3 pubblicato identificato; non effettuato bind |
| `com.huami.watch.transport.DataTransportService` | Service / true esplicito | nessuna nel manifest | `com.huami.watch.transport.DataTransportService`; nessuna categoria | nessuno | B; trasporto generico per nome, relazione alla musica D; non avviato |
| `com.huami.watch.companion.bt_connect.BGService_msg` | Service / true esplicito | nessuna nel manifest | `cn.com.huami_service.action`; nessuna categoria | nessuno | B; nessuna prova di flusso MP3; non avviato |
| `com.huami.moving.sport.ui.activity.import.SportFitImportActivity` | Activity / true esplicito | nessuna | `VIEW`, `DEFAULT`, `BROWSABLE` | file/content/http/https, filtri path `.fit`/`.FIT`, uno con `*/*` | B; importazione sportiva, non audio; nessuna query MP3 risolta; non avviata |
| `androidx.core.content.FileProvider` | Provider / false esplicito | nessuna nel manifest | nessuna | autorità `com.huami.watch.hmwatchmanager.file`; grantUriPermissions=true | C per accesso diretto; può condividere solo URI concessi da Zepp, non è un ingresso di upload |
| `com.huami.account.sso.provider.AccountInfoProvider` | Provider / true esplicito | readPermission=`com.huami.watch.hmwatchmanager.permission.ACCOUNT_INFO` | nessuna | autorità nell'inventario | Escluso: account SSO, nessuna relazione musicale; non interrogato |

L'assenza di permission nel manifest non garantisce l'assenza di controlli runtime,
né l'esistenza di un protocollo utilizzabile. Non sono stati inviati messaggi
Binder, startService, broadcast o query a provider per indovinare contratti.
I Receiver dichiarati non forniscono nel manifest un contratto per l'upload MP3.

Gli altri FileProvider di Zepp (feedback, bridge, recorder, picture selector,
upgrade, ReactNativeBlobUtil e condivisione GPX/watchface/MMS) risultano non
esportati; `grantUriPermissions=true`, quando presente, non li rende liberamente
accessibili e non consente di inserirvi un file dall'esterno.

### Deep link dichiarati dal launcher

Per le route `VIEW` del launcher le categorie sono `DEFAULT` e `BROWSABLE`:

- `app://hm.xiaomi.com/health` con pathPrefix `/health`;
- `amazfit://com.huami.watch.hmwatchmanager/action`;
- `amazfit://gpx`;
- scheme `huamifitWXTSX8J`;
- file `.dial`, con i filtri e MIME wildcard riportati nell'inventario;
- `amazfit://nfccard/create_car_card`, `/create_car_card_jh`, `/create_huami_card`;
- `amazfit://com.huami.watch.hmwatchmanager/zepppay`;
- `zepp://auth-return`.

Sono inoltre dichiarate action di notifica/find-phone. Nessun filtro del
launcher dichiara `audio/mpeg` o un path musicale. La route generica `/action`
potrebbe effettuare dispatch tramite parametri, ma il suo contratto è **D, non
verificato**: non sono stati inventati parametri o provate destinazioni interne.
Le route OAuth, pagamento, GPX e watchface non sono state invocate.

## 5. Risultati sul dispositivo

| Prova | Risultato verificato | Limite |
| --- | --- | --- |
| Enumerazione e identificazione APK | package, label, versione e split confermati | vale per questa installazione |
| Manifest base + split | inventario completo; componenti musicali interni | funzione effettiva dedotta dai nomi, non dal bytecode |
| `SEND audio/mpeg` verso Zepp | `No activities found` | risoluzione, non invio file |
| `SEND_MULTIPLE audio/mpeg` verso Zepp | `No activities found` | risoluzione, non invio file |
| `VIEW content://... audio/mpeg` verso Zepp | `No activities found` | URI sintetico; nessuna lettura |
| Avvio launcher esplicito | `Status: ok`, `LaunchState: WARM`, Activity `StartUpActivity`, TotalTime 268 ms | prova solo di avvio normale ADB |

Unica invocazione eseguita, derivata dal componente launcher realmente risolto:

```powershell
& $adb shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n com.huami.watch.hmwatchmanager/com.xiaomi.hm.health.activity.StartUpActivity
```

Il successivo dump Activity mostra il task Zepp con `MainTabActivity`. Non è
stata verificata visivamente la schermata di upload. Il log dell'avvio è in
`tools/zepp-intents/launcher-test.txt`. Nessuna SecurityException durante questa
prova; nessun componente interno è stato avviato per testarne il rifiuto.

Non è stata trovata una candidata accessibile con evidenza concreta di un
contratto musicale. Pertanto il test condizionale con MP3 autorizzato e il
prototipo di upload **non sono stati eseguiti**, come richiesto. Nessun file
inviato, nessun trasferimento all'orologio, nessuna conferma di trasferimento
sollecitata. Gli script sono strumenti di inventario, non un prototipo musicale.

## 6. Android moderno e limiti

La package visibility da Android 11 può filtrare `getPackageInfo` e
`queryIntentActivities` in una normale app. Una futura verifica di presenza
richiederebbe una `<queries><package .../></queries>` mirata al package
verificato, non `QUERY_ALL_PACKAGES`. La visibility non concede accesso a
componenti interni. Android distingue l'avvio di un'Activity dalle query di
visibilità; un Intent esplicito non aggira exported e permission.
[Documentazione Android sulla visibility](https://developer.android.com/training/package-visibility/use-cases).

I valori exported predefiniti sono interpretati secondo tipo di componente e
targetSdk. I filtri sono contratti di risoluzione, non una prova che il destinatario
accetti qualunque file né che avvii il flusso desiderato.
[Activity](https://developer.android.com/guide/topics/manifest/activity-element),
[Intent e filtri](https://developer.android.com/guide/components/intents-filters).

Se emergesse un vero destinatario, SyncBeat dovrebbe concedere temporaneamente
lettura dell'URI posseduto tramite `FLAG_GRANT_READ_URI_PERMISSION`, usando
`data`/`ClipData` o `EXTRA_STREAM` soltanto secondo il contratto verificato.
Non usare `file://`, non concedere scrittura, non simulare il risultato del picker.
Una concessione dal processo ADB non dimostrerebbe che SyncBeat, proprietaria
del file, abbia consegnato correttamente l'URI.
[Condivisione sicura Android](https://developer.android.com/training/secure-file-sharing/share-file).

Un picker aperto **da Zepp** riceve un risultato nel contesto della richiesta di
Zepp. Aprire un picker da SyncBeat non permette di restituire arbitrariamente
quel risultato a un'Activity Zepp. La pubblicazione in Download resta coerente
con il flusso manuale SAF.
[Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files).

`BIND_JOB_SERVICE` è riservato al sistema: non è un permesso runtime da chiedere
all'utente per accedere a EarbudMusicDownloadService.
[Riferimento permission Android](https://developer.android.com/reference/android/Manifest.permission#BIND_JOB_SERVICE).

ADB usa l'UID shell, con capacità diverse da una normale app. Le query negative
e i manifest sono evidenze utili, ma un'eventuale integrazione positiva richiederà
una prova da UID ordinario, app in foreground e consenso esplicito prima di
qualunque trasferimento. Non sono state verificate varianti Zepp, vecchie
versioni Android, iOS o Windows.

## 7. Fonti Zepp e prossimi passi

Le ricerche nella documentazione ufficiale non hanno identificato un contratto
Android pubblico per il caricamento MP3. Questo è un esito della ricerca,
non una dichiarazione universale di inesistenza. Le istruzioni ufficiali di
importazione musicale descrivono l'interazione nell'app Zepp, anche per Active 3
Premium; non documentano Intent, extra o endpoint IPC.
[Istruzioni Amazfit](https://www.amazfit.jp/blogs/upyourgame/music1).

1. Mantenere il flusso funzionante: Download/SyncBeat → selezione manuale in
   Zepp → trasferimento alla Musica originale dell'orologio.
2. Chiedere al supporto Zepp un contratto documentato per aprire la pagina Musica
   e passare un `content://` URI; nessun messaggio è stato inviato al supporto.
3. Se si desidera approfondire quale Activity usa l'orologio specifico, aprire
   manualmente Musica in Zepp e osservare il componente con ADB. Questo può
   confermare la funzione, ma non cambia da solo il valore exported.
4. Ripetere l'inventario dopo aggiornamenti Zepp. Solo con una nuova interfaccia
   concreta preparare un prototipo isolato e un MP3 sintetico/autorizzato;
   verificare pagina e accettazione file, fermandosi prima del trasferimento.

### Verifiche degli strumenti

`inspect-zepp-intents.ps1` eseguito sia senza package (enumerazione) sia con il
package identificato (raccolta completa di base/split, JSON e query). Due test
Python verificano UTF-8/UTF-16, exported predefinito, esclusione di `<queries>`,
filtri multipli e permission ereditate dagli Alias: **2 test superati**.

Verifiche del repository dopo la raccolta: `dart format .` (50 file, nessuna
modifica), `flutter analyze` (nessun problema), `flutter test
test/public_audio_storage_test.dart test/local_audio_library_test.dart`
(**11 test superati**) e `git diff --check` (nessun errore). Non sono state
ripetute build o installazioni perch? questo studio aggiunge soltanto script e
documentazione. Nessun commit o push.

**Classificazione finale: C — possibile soltanto aprire Zepp.** Nessuna prova
attuale sostiene A (pagina e file) o B (pagina musicale senza file).
