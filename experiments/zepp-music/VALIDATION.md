# Verifica del 16 novembre 2026

## Eseguito

Ambiente di compilazione: JDK 17, Gradle 8.13, Android Gradle Plugin 8.9.1,
Android SDK 35 / Build Tools 35.0.0. Compilazione del solo progetto isolato,
nessuna modifica alle dipendenze o al lockfile Flutter.

```sh
./gradlew clean testDebugUnitTest assembleDebug lintDebug
```

- APK debug generato e firma debug verificata.
- Manifest del binario verificato: package separato
  `com.antonyjr0.syncbeat.zeppprototype`, minSdk 26, targetSdk 35.
- Permessi del binario: BLUETOOTH fino ad Android 11, BLUETOOTH_CONNECT;
  nessun INTERNET, scansione o posizione.
- 21 test di protocollo + 2 test UI, tutti passati.
- Lint Android: nessun problema. Gradle segnala API del sistema di build
  deprecate in vista di Gradle 9; il wrapper resta fissato a 8.13.
- Rendering delle View Android a 320 e 390 px: testi e pulsanti leggibili,
  campo chiave mascherato, upload disabilitato prima della verifica.

I test includono: framing frammentato/concatenato e CRC, EOF, ricomposizione
cifrata, ordine e bounds, ECDH con chiave remota invalida, handshake completo
con peer sintetico, servizi cifrati e upload, indice modulo 256, chunk unsigned
32768, ACK errato e ACK finale mancante, servizio music assente, versione non
supportata, rifiuto auth, sessione errata, ping, offset di ripresa nonzero,
chiusura e upload prima dell'inizializzazione, blocco UI senza dispositivo,
protezione del campo chiave e svuotamento all'uscita.

## Non eseguito

- Nessuna connessione all'Active 3 Premium di Antonio.
- Nessuna chiave reale recuperata, letta o usata dal prototipo durante lo sviluppo.
- Nessun MP3 scritto su un orologio reale.
- Nessuna misura di velocita', stabilita', batteria o comportamento radio.
- Nessuna prova di indicizzazione, riproduzione o ritorno a Zepp sul suo firmware.
- Nessuna integrazione nell'interfaccia Flutter principale e nessun test completo
  di regressione Flutter (i file runtime Flutter non sono stati modificati).

## Cosa renderebbe riuscita la futura prova hardware

Autenticazione + capacita' music V3, MP3 piccolo confermato e riproducibile
nel lettore nativo, poi un brano normale, infine ritorno a Zepp con attivita'
sincronizzate. Se passa solo il Bluetooth o solo l'ACK finale, la verifica
end-to-end non e' completa. Interruzioni, duplicati/file parziali e ripresa
richiedono prove successive controllate; nessuna affidabilita' e' promessa qui.
