# Licenze e provenienza del prototipo

## Versione sperimentale

Il lavoro combinato di questo branch e' distribuito sotto **AGPL-3.0-or-later**.
Il testo integrale e' nel `LICENSE` alla radice e nell'app, sezione Licenza.
Il codice preesistente di Antonio mantiene il proprio avviso MIT, conservato
in `LICENSE-MIT`. `main` non e' stato modificato: il cambio qui riguarda la
versione sperimentale che incorpora il codice seguente, non una riscrittura
retroattiva delle licenze dei contributi originali.

Non e' una consulenza legale per altri modi di distribuzione. Distribuendo
un APK di questo lavoro, rendere disponibile anche il sorgente corrispondente
della stessa revisione e le istruzioni necessarie a compilarlo. Non separare
l'APK da questo riferimento. Le dipendenze di test non sono incluse nell'APK.

## Gadgetbridge

- Progetto: Freeyourgadget/Gadgetbridge.
- Sorgente: https://codeberg.org/Freeyourgadget/Gadgetbridge
- Revisione consultata e fissata: `e5b4a77c81cbe08ebbc4fd59ee943a0e19326e23`.
- Licenza: GNU Affero General Public License, versione 3 o successiva.
- Copyright delle parti adattate: José Rebelo (2022-2026), Andreas Shimokawa (2022-2024).
- Routine CRC adattata da CheckSums.java: Copyright (C) 2015-2025 Andreas
  Shimokawa, Carsten Pfeiffer, Damien Gaignon, Daniele Gobbetti, José Rebelo,
  Petr Vaněk, vappster.
- Modifiche: Antonio Guarini, 16 novembre 2026.

Corrispondenza dei file upstream (sotto `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/`):

| File del prototipo | Origine upstream | Modifiche |
| --- | --- | --- |
| `ECDH_B163.java` | `util/ECDH_B163.java` | Package e rimozione annotazione; aritmetica mantenuta, formattazione. |
| `Wire.java` | `service/devices/huami/zeppos/ZeppOsBtbrSupport.java`, `util/CheckSums.java` | Riduzione a framing/CRC e stream sincroni con limiti; AES JCA senza log. |
| `ChunkCodec.java` | `service/devices/huami/Huami2021ChunkedEncoder.java`, `Huami2021ChunkedDecoder.java` | Riduzione al protocollo esteso, controllo bounds/ordine/CRC, nessun log di payload o chiavi. |
| `ZeppSession.java` | `service/devices/huami/zeppos/ZeppOsBtbrSupport.java`, `services/ZeppOsAuthenticationService.java`, `services/ZeppOsServicesService.java`, `services/filetransfer/ZeppOsFileTransferImpl.java`, `ZeppOsFileTransferV3.java`, `operations/ZeppOsMusicUploadOperation.java` | Percorso esplicito Classic, auth con SecureRandom, soli servizi necessari, solo V3, un MP3/sessione, niente reset, firmware, eliminazione o sincronizzazione attivita'; avanzamento dopo ACK, bounds e controlli aggiunti. |

La copia dell'implementazione ECDH proviene dal port Java di tiny-ECDH-c
indicato nel commento originale di Gadgetbridge. Il progetto C originale:
https://github.com/kokke/tiny-ECDH-c , rilasciato sotto Unlicense; testo conservato
in `app/src/main/assets/tiny-ECDH-LICENSE.txt`.

L'app mostra attribuzione, assenza di garanzia e licenza. Il sorgente
corrispondente comprende i file nel branch `experiment/zepp-native-music`
di `https://github.com/antonyjr0/syncbeat`, il wrapper Gradle e questa guida.
Non sono richiesti segreti o file privati per compilare il prototipo.

## Cosa non e' incluso

Non e' incluso il resto dell'app Gadgetbridge, il suo database, le sue
funzioni di salute, firmware, account o sincronizzazione. Non e' un prodotto
ufficiale Amazfit/Zepp ne' una versione approvata dai manutentori Gadgetbridge.
