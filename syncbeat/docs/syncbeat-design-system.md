# SyncBeat — design system

Restyling Material 3 per Android e Windows, 5 novembre 2026.

## Identità e logo

Interfaccia sobria con fondali blu profondi, superfici distinte e accenti blu,
ciano e viola riservati ad azioni e selezioni. Il logo ufficiale è
`assets/branding/app_icon.png`, identificato dalla relativa README e dallo script
`scripts/generate-app-icons.ps1`. Nessun asset del logo è stato modificato o
rigenerato. SHA-256 originale:
`888E75C2060A0496CDC6EAD829019B5B6B75E039DD7985E9B01F82F96C252982`.

Android usa `@mipmap/ic_launcher`; l'icona adattiva usa
`@drawable/ic_launcher_foreground` e `@color/ic_launcher_background` (nero,
lasciato invariato perché parte della configurazione dell'icona).
Windows usa `windows/runner/resources/app_icon.ico` tramite `Runner.rc`.
L'intestazione Flutter mostra ora direttamente l'asset ufficiale, registrato
nel pubspec, al posto del simbolo generico delle cuffie.

### Campioni estratti dall'immagine

Pixel letti con System.Drawing, coordinate x,y dall'angolo superiore sinistro.
Sono campioni reali, non colori piatti dominanti: il logo contiene gradienti,
texture e antialiasing.

| Posizione | HEX | Utilizzo |
| --- | --- | --- |
| 500,200 | `#75D1FD` | Ciano, primario scuro |
| 650,185 | `#6491FB` | Blu, seed Material 3 |
| 1000,710 | `#B562FA` | Viola, riferimento per il secondario |
| 700,830 | `#050E20` | Riferimento per fondali profondi |
| 640,1000 | `#0A1B3A` | Riferimento per superfici blu |
| 700,400 | `#071123` | Sfondo scuro |
| 900,300 | `#3B258D` | Viola profondo |

### Palette applicativa definitiva

Le tonalità derivate mantengono l'identità e rendono leggibili testi e controlli.
Successo e avviso sono colori semantici aggiuntivi, non estratti dal logo.

| Ruolo | Chiaro | Scuro |
| --- | --- | --- |
| Primario | `#2055A6` | `#75D1FD` |
| Su primario | `#FFFFFF` | `#071123` |
| Secondario | `#7040A0` | `#D2ACFF` |
| Su secondario | `#FFFFFF` | `#29133F` |
| Contenitore secondario | `#F0DEFF` | `#402559` |
| Su contenitore secondario | `#29133F` | `#F0DEFF` |
| Accento / terziario | `#00658A` | `#75D1FD` |
| Su terziario | `#FFFFFF` | `#071123` |
| Sfondo | `#F5F7FC` | `#071123` |
| Superficie | `#FCFCFF` | `#111E34` |
| Superficie contenitore bassa | `#F0F3FA` | `#17263E` |
| Testo principale | `#14213A` | `#E7EDFA` |
| Testo secondario | `#4D5D75` | `#BAC6DB` |
| Bordo controlli | `#687891` | `#8292AC` |
| Bordo separatori | `#D1DAE8` | `#34445F` |
| Successo | `#216849` | `#85DDB0` |
| Avviso | `#805300` | `#FFD180` |

Gli altri ruoli (contenitori primari, inverse, error/errorContainer e rispettivi
foreground) sono generati da `ColorScheme.fromSeed(#6491FB)` con la luminosità
richiesta, secondo Material 3 nell'SDK Flutter del progetto. Non duplicarli
nelle schermate: usare il ruolo del ColorScheme. Gli errori usano icona, testo
esplicativo e coppia errorContainer/onErrorContainer, non soltanto colore.

## Temi e componenti

`lib/theme/syncbeat_theme.dart` centralizza ColorScheme, ThemeData, tipografia,
app bar, card, campi, pulsanti, icon button, dialog, navigation bar/rail,
progress indicator, snackbar e separatori. `SyncBeatStatusColors` è una
ThemeExtension per successo e avviso, con interpolazione tra temi.

`lib/app.dart` configura lightTheme/darkTheme e `ThemeMode.system`. Nel codice
iniziale non esistevano selezione del tema, relativa preferenza persistente o
schermata impostazioni: non sono stati aggiunti nuovi selettori o nuove
schermate. Tutte le preferenze applicative esistenti restano intatte.

Dashboard, autenticazione, configurazione, playlist, importazione, brani e stati
vuoti usano ruoli di tema al posto della precedente palette verde/arancio.
Il dialog Jamendo/MP3 locale usa gli stessi ruoli e i colori semantici.
Dialog YouTube (ricerca, risultati, autorizzazioni, conversione, download),
libreria locale, player e dialog informativi ereditano il tema centrale tramite
i loro componenti Material esistenti. Non sono state create schermate assenti.
OAuth, matching, download, cache, storage e integrazioni native non sono cambiati.

## Tipografia, spazi e interazioni

Tipografia Material 3 di Flutter, senza font o dipendenze aggiuntive; fallback
di sistema su Android e Windows. Usare headlineSmall per il marchio,
titleLarge per sezioni, titleMedium per pannelli, body per contenuti e label
per dettagli. Conservare il ridimensionamento del testo di sistema.

Spazi esistenti coerenti: 8–14 dp tra controlli correlati, 16–22 dp nei pannelli,
28–30 dp tra sezioni; contenuto desktop limitato a 1120 dp. Bordi da 8–10 dp,
card senza elevazione. Pulsanti e icon button hanno target minimo 48 × 48 dp.
Hover, pressed e disabled seguono gli stati Material 3; i pulsanti mostrano
un bordo primario di 2 dp al focus tastiera. I campi attivi usano lo stesso
indicatore. Gli stati di configurazione includono testo e icone distintive.

I breakpoint tengono conto anche della scala del testo: azioni sotto il pannello
account a larghezze ridotte, griglia di stato con colonne variabili, importazione
verticale e righe brano adattate su smartphone. Contenuto principale scrollabile.

## Gradienti

Il logo originale contiene ciano → blu → viola nell'anello e nel lettering.
Preservare questo gradiente nell'asset. Non ripeterlo in pannelli, pulsanti o
testi: superfici uniformi garantiscono equilibrio e contrasto prevedibile.

## Validazione e limiti

`test/design_system_test.dart` misura il contrasto WCAG AA (almeno 4.5:1)
dei testi principali/secondari, azioni, messaggi di errore e stati semantici
nei due temi. Questo controllo non equivale a un audit completo di accessibilità.
`test/responsive_layout_test.dart` usa il tema reale a 320, 393, 600, 900 e
1440 dp, con testo 1×, 1.5× e 2× in entrambi i temi, verificando overflow,
accessibilità delle azioni, leggibilità dell'account e apertura del dialog YouTube.

Da verificare manualmente su dispositivi reali: resa light/dark su Android e
Windows, resize continuo, navigazione completa da tastiera, screen reader,
focus, OAuth interattivo, riproduzione e download autorizzati end-to-end.
Non è stata effettuata una verifica visiva dell'app nativa durante questa sessione.

### Risultati eseguiti

- `dart format .`: 50 file controllati, formattazione completata.
- `flutter analyze`: nessun problema.
- `flutter test`: 142 test superati, incluso contrasto e matrice responsive.
- `flutter build windows`: riuscita; `build/windows/x64/runner/Release/syncbeat.exe`.
- `flutter build apk --debug`: riuscita; `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: nessun errore; hash del logo confermato invariato.

La build Android segnala un avviso preesistente di compatibilità futura Kotlin
Gradle Plugin per `appwrite` e `flutter_web_auth_2`. Non sono state aggiornate
dipendenze durante il restyling. Una prima esecuzione ha rilevato un'espressione
`const` non valida durante la migrazione dei widget: corretta prima delle
validazioni finali sopra riportate. Il formatter inizialmente aveva completato
la scrittura ma non poteva aggiornare la telemetria nel sandbox; la successiva
esecuzione autorizzata è terminata correttamente.

File modificati/aggiunti: `lib/app.dart`, `lib/theme/syncbeat_theme.dart`,
`lib/features/audio_sources/audio_match_dialog.dart`, `pubspec.yaml`,
`test/design_system_test.dart`, `test/responsive_layout_test.dart` e questo documento.
Nessun commit o push effettuato.
