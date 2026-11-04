# Correzioni del 4 novembre 2026

## Problemi corretti

- **Login Spotify Windows bloccato dopo un errore.** Riprodotto AUD-01:
  il listener lasciava occupata la porta 8888 se il browser non partiva.
  Il server viene ora aperto prima del browser e chiuso in tutti i percorsi,
  compresi eccezioni e timeout. I percorsi HTTP estranei al callback ricevono
  404 senza consumare il tentativo. Sono rifiutati accessi sovrapposti.
- **Callback Android di un vecchio accesso.** Il listener accetta solo schema,
  host, percorso e state del tentativo corrente; non rilegge il vecchio link
  iniziale. La sottoscrizione viene annullata al termine di ogni tentativo.
  Il manifest disabilita il gestore Flutter concorrente, lasciando il callback
  ad app_links, secondo la [documentazione Flutter](https://docs.flutter.dev/release/breaking-changes/deep-links-flag-change).
- **Salvataggi concorrenti di associazione e conferme.** La scelta e le conferme
  vengono scritte nello stesso record. Le modifiche sullo stesso brano sono
  serializzate anche tra repository diversi. Una conferma tardiva per un vecchio
  video non può ripristinarlo dopo una sostituzione. Il dialogo blocca i controlli
  durante il ripristino iniziale e durante il salvataggio, acquisendo prima le
  conferme del video interessato.
- **Associazione corrotta impossibile da sostituire.** I valori salvati di tipo
  errato producono un errore gestibile; una nuova scelta esplicita ripara il record
  senza ereditare conferme. La coda dei salvataggi continua anche dopo un errore.
- **Un manifest danneggiato blocca la libreria audio.** I record pubblicati sono
  validati prima dell'uso, compresi tipi, data, nome, dimensione e hash. I record
  malformati vengono ignorati individualmente. La scansione dello staging tollera
  file scomparsi o non leggibili. Non viene cancellato audio dell'utente.

## Verifiche

- `flutter analyze --no-pub`: nessun problema.
- `flutter test --no-pub`: 123 test superati, incluse nuove regressioni OAuth
  Windows/Android, salvataggi concorrenti e manifest Android malformati.
- `flutter test --no-pub audit/known_failures_test.dart`: tre prove superate.
  AUD-02 e AUD-03 risultavano già corretti nel codice prima di queste modifiche;
  AUD-01 falliva ed è stato corretto in questo intervento.
- `flutter build apk --release --no-pub`: APK release compilato. Restano gli
  avvisi KGP di appwrite/flutter_web_auth_2, che non impediscono questa build.

I test OAuth verificano server HTTP loopback e callback Android simulati, senza
credenziali o richieste a Spotify. Login reale e ritorno dal browser sul telefono
richiedono ancora collaudo con account/dispositivo. Un tentativo OAuth in corso
non viene ripreso dopo la terminazione del processo.

L'audit del 3 novembre resta una fotografia storica; gli esiti sopra aggiornano
specificamente AUD-01/02/03 e la configurazione/callback descritti in AUD-05.
