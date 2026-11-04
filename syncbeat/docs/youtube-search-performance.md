# Ricerca YouTube: ottimizzazione del 4 novembre 2026

Il flusso precedente usava `--dump-json --skip-download`: evitava il download,
ma estraeva i dettagli di ogni video delle due query, fino a 15 risultati.
Questo introduceva molte richieste aggiuntive prima di mostrare la lista.

La ricerca ora aggiunge `--flat-playlist`, documentato nel
[README ufficiale yt-dlp](https://github.com/yt-dlp/yt-dlp#general-options):
vengono letti i risultati delle pagine di ricerca senza aprire ogni watch page.
Le due query generica e auto-generated, la deduplicazione, il ranking e la scelta
manuale restano attivi. I campi mancanti non ricevono punti nel ranking; la ricerca
non dimostra disponibilità al download o diritti sul contenuto.

Su Android la policy ammette la nuova opzione solo nelle ricerche e il servizio
non inizializza FFmpeg per cercare o aggiornare il motore. Il bridge conserva
anche uploader e thumbnails: le miniature flat sono lette dal modello Dart.
La ricerca ha timeout di 30 secondi, socket timeout di 8 secondi e un retry;
non riduciamo i limiti di download/conversione.

## Misure

Prove eseguite sul PC Windows, solo metadati pubblici, nessun audio scaricato:

- comando diretto, due query VELENO/Tananai, 15 risultati: circa 3,24 secondi;
- `flutter test --no-pub audit/youtube_live_test.dart`, con il provider aggiornato:
  15 risultati, 10 classificati, 2.943 ms, registrazione originale al primo posto.

Evidenza locale esclusa dal repository: `tools/audit/youtube-live.json`.
Il tempo precedente di almeno un minuto è quanto segnalato dall'utente sul
telefono; non è una misura comparativa sullo stesso dispositivo. Il tempo Android
va verificato installando l'APK aggiornato, soprattutto alla prima ricerca e con
rete mobile. I risultati vengono tuttora restituiti insieme al completamento
delle due ricerche; non sono visualizzati progressivamente.

## Verifica

- 124 test Flutter superati, incluso il ranking sui metadati flat reali acquisiti
  e la conservazione della ricerca supplementare.
- `flutter analyze --no-pub`: nessun problema.
- 15 test nativi Android superati, inclusi accettazione della ricerca flat e
  rifiuto dell'opzione nei download; compilazione dell'APK release.

Conferme salvate, download autorizzati, conversione e file esistenti mantengono
il comportamento precedente.

## Prova sul telefono collegato

È disponibile `audit/phone_youtube_search.dart`, un entrypoint diagnostico che
esegue la stessa ricerca e lo stesso bridge nativo senza login Spotify. Mostra
durata, numero di candidati e primo risultato; scrive una riga JSON identificata
da `SYNCBEAT_SEARCH_PROBE` nei log dell'app. Non scarica audio.

Compilazione esplicita: `flutter build apk --release --no-pub -t audit/phone_youtube_search.dart`.
Questa build usa lo stesso package dell'app: conservare prima l'APK normale e
ripristinarlo dopo la prova. La build diagnostica è stata preparata localmente in
`tools/phone-search-probe.apk`; quella normale resta in
`build/app/outputs/flutter-apk/app-release.apk` e `tools/phone-production.apk`.

La prima connessione era un dispositivo errato M2006C3LVG, sul quale
l'installazione è stata rifiutata. Dopo il collegamento dello Xiaomi 15T corretto
(modello 25069PTEBG) e l'abilitazione del debug USB da parte dell'utente,
l'installazione del test è riuscita conservando i dati dell'app esistente.

Misure reali del 4 novembre, ricerca Tananai / VELENO:

| Prova | Durata | Risultati | Primo candidato |
| --- | --- | --- | --- |
| Schermo acceso | 4.697 ms | 15 | VELENO, PzYnwqUGI7Q |
| Schermo spento durante la ricerca | 4.728 ms | 15 | VELENO, PzYnwqUGI7Q |

Per la seconda prova i log PowerManager e Flutter correlati mostrano:
avvio circa 1793797358,929 (epoch), spegnimento tramite tasto a 1793797359,590,
stato Dozing a 1793797360,372 e risultato a 1793797363,657, senza riaccensione
intermedia. Il completamento avviene quindi mentre lo schermo è già spento.
La prova copre una ricerca breve; non dimostra resistenza a force-stop,
terminazione del processo o lunghe sospensioni Doze.

Al termine è stata reinstallata con successo l'app normale aggiornata tramite
`adb install -r`, senza cancellare dati. Nessun audio è stato scaricato.
Evidenze locali: `tools/phone-search-results.log`,
`tools/phone-search-screen-timeline.log`, `tools/phone-search-verified.json`.
