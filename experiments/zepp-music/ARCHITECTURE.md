# Architettura e limiti intenzionali

App Android nativa separata per validare l'hardware prima dell'integrazione Flutter.
Nessun modulo YouTube/download o archivio dell'app principale viene modificato.

1. `PrototypeActivity`: consenso locale esplicito per dispositivo e upload;
   selettore MP3 Android; chiave in campo mascherato non persistente;
   permesso CONNECT su Android 12+, nessuna discovery o mutazione dei bond.
2. `Wire`: frame Classic 0x55/cmd/seq/len/CRC16/0xaa, stream read-exactly,
   lunghezza unsigned limitata a 65535 e controllo integrita'.
3. `ChunkCodec`: protocollo Huami2021 esteso, pacchetti e ricomposizione con
   bounds/ordine, AES conforme al firmware e CRC32. Nessun payload loggato.
   L'ECB qui e' imposto dal protocollo esistente, non una scelta per cifrare
   nuovi archivi o dati persistenti.
4. `ZeppSession`: channel mapping, session nonce, ECDH B163 + prova AES con
   chiave Zepp, servizi 0x0000/0x000d, capacita' V3 e `music`, upload `music://file`.
5. Upload: non compresso, CRC32 dichiarato, blocchi negoziati frammentati secondo
   MTU Classic. Progresso solo dopo ACK con indice atteso modulo 256; successo
   trasporto solo dopo ACK dell'ultimo blocco. Presenza/riproduzione nel player
   rimangono una verifica hardware distinta.

## Timeout, annullamento, limiti

- Una sola sessione e un solo MP3 per connessione. Nessun retry invisibile.
- Worker singolo; timer totale 30s per lettura file, 120s per inizializzazione,
  300s di attesa fra verifica e upload, 600s per upload.
  Il timer chiude il socket per sbloccare read/connect. Non e' un timeout radio per blocco.
- Uscire dall'Activity chiude socket e chiavi; callback obsolete scartate per generazione.
- Solo file fino a 32 MiB e metadati <=200 byte. Rifiutati separatori query e
  controlli invece di inventare un escaping non verificato.
- Rifiutati servizi/versioni inattesi, offset di ripresa nonzero, CRC e ACK errati.
- Non implementati V1/V2, BLE, Wi-Fi, lista/cancellazione musica, aggiornamenti
  firmware, reset, impostazioni, riconnessione automatica e sincronizzazione salute.
- La disconnessione non garantisce rollback di un file parziale.

## Prove

`ProtocolTest` esegue il vero client contro uno stream peer sintetico: non mocka
semplicemente un booleano di successo. Verifica ECDH, AES, servizi cifrati, upload
con rollover dell'indice, errori e ACK finale mancante. Il peer e il client derivano
comunque dallo stesso protocollo interpretato: possono condividere assunzioni
sbagliate. Non sostituisce test con firmware reale e acquisizioni autorizzate.

`UiTest` usa rendering Android nativo a 320 e 390 px e controlla che l'upload
sia disabilitato prima della verifica. Non e' una connessione a un dispositivo.
