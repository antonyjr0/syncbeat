/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Adapted 2026-11-16 from Gadgetbridge (C) 2022-2025 José Rebelo:
 * ZeppOsBtbrSupport, ZeppOsAuthenticationService, ZeppOsServicesService,
 * ZeppOsFileTransferV3, ZeppOsFileTransferImpl, ZeppOsMusicUploadOperation.
 * Reduced to explicit Classic auth/capabilities/one MP3. See THIRD_PARTY_NOTICES.md. */
package com.example.syncbeat.zepp;

import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;

public final class ZeppSession implements AutoCloseable {
  public static final String SERIAL_UUID = "00000022-0000-3512-2118-0009af100700";
  static final String WRITE = "00000016-0000-3512-2118-0009af100700",
      READ = "00000017-0000-3512-2118-0009af100700";
  static final String FILE_SEND = "00000023-0000-3512-2118-0009af100700",
      FILE_RECEIVE = "00000024-0000-3512-2118-0009af100700";

  public interface Events {
    void status(String text);

    void progress(int acknowledgedBytes, int total);
  }

  private final InputStream in;
  private final OutputStream out;
  private final Events events;
  private final ChunkCodec codec = new ChunkCodec();
  private final Map<String, Integer> channels = new HashMap<>();
  private final Map<Integer, Boolean> services = new HashMap<>();
  private int sequence, session = -1, chunkSize;
  private boolean ready, closed;

  public ZeppSession(InputStream in, OutputStream out, Events events) {
    this.in = in;
    this.out = out;
    this.events = events;
  }

  public static byte[] parseKey(char[] value) throws IOException {
    int start =
        value.length == 34 && value[0] == '0' && (value[1] == 'x' || value[1] == 'X') ? 2 : 0;
    Wire.require(value.length - start == 32, "La chiave deve contenere 32 cifre esadecimali");
    byte[] key = new byte[16];
    for (int i = 0; i < 16; i++) {
      int a = Character.digit(value[start + i * 2], 16),
          b = Character.digit(value[start + i * 2 + 1], 16);
      if (a < 0 || b < 0) {
        Arrays.fill(key, (byte) 0);
        throw new IOException("Chiave non valida");
      }
      key[i] = (byte) ((a << 4) | b);
    }
    return key;
  }

  public void initialize(byte[] authKey) throws IOException {
    Wire.require(authKey.length == 16 && session < 0 && !closed, "Sessione non valida");
    events.status("Negoziazione Bluetooth Classic");
    send(1, new byte[0]);
    Wire.Packet ch = waitCommand(2);
    ByteBuffer b = Wire.le(ch.payload);
    Wire.require(b.remaining() >= 3 && Wire.u(b.get()) == 1, "Versione Classic non supportata");
    int count = b.getShort() & 65535;
    Wire.require(count <= 128, "Troppi canali");
    for (int i = 0; i < count; i++) {
      String uuid;
      try {
        uuid = UUID.fromString(Wire.string(b, 64)).toString();
      } catch (IllegalArgumentException e) {
        throw new IOException("Identificatore canale non valido");
      }
      Wire.require(b.remaining() >= 2, "Canale incompleto");
      channels.put(uuid, b.getShort() & 65535);
    }
    Wire.require(
        channels.containsKey(WRITE) && channels.containsKey(READ), "Canali Zepp OS mancanti");
    int nonce = new SecureRandom().nextInt();
    send(3, Wire.buffer(4).putInt(nonce).array());
    b = Wire.le(waitCommand(4).payload);
    Wire.require(
        b.remaining() >= 8 && b.getInt() == nonce && Wire.u(b.get()) == 1,
        "Sessione Classic rifiutata");
    session = Wire.u(b.get());
    int mtu = b.getShort() & 65535;
    Wire.require(mtu >= 32 && mtu <= 65535, "MTU Classic non valido");
    codec.mtu = mtu;
    authenticate(authKey);
    events.status("Lettura dei servizi disponibili");
    sendService(0, new byte[] {3}, false);
    b = Wire.le(waitService(0));
    Wire.require(b.remaining() >= 3 && Wire.u(b.get()) == 4, "Lista servizi non riconosciuta");
    count = b.getShort() & 65535;
    Wire.require(count <= 1024 && count * 3 <= b.remaining(), "Lista servizi incompleta");
    for (int i = 0; i < count; i++) {
      int endpoint = b.getShort() & 65535, enc = Wire.u(b.get());
      Wire.require(enc <= 1, "Cifratura servizio sconosciuta");
      services.put(endpoint, enc == 1);
    }
    Wire.require(
        services.containsKey(13), "Il firmware non espone il servizio di trasferimento file");
    sendService(13, new byte[] {1}, services.get(13));
    b = Wire.le(waitService(13));
    Wire.require(b.remaining() >= 10 && Wire.u(b.get()) == 2, "Capacita' trasferimento incomplete");
    Wire.require(Wire.u(b.get()) == 3, "Questo prototipo accetta solo file transfer V3");
    chunkSize = b.getShort() & 65535;
    b.getInt();
    count = b.getShort() & 65535;
    Wire.require(chunkSize > 0 && count <= 256, "Capacita' trasferimento non valide");
    boolean music = false;
    for (int i = 0; i < count; i++) if (Wire.string(b, 128).equals("music")) music = true;
    Wire.require(music, "Il firmware non dichiara il servizio music: upload non tentato");
    Wire.require(channels.containsKey(FILE_SEND), "Canale upload musicale assente");
    ready = true;
    events.status(
        "Autenticazione riuscita. Servizio music presente (V3 / Classic). Nessun brano inviato.");
  }

  private void authenticate(byte[] authKey) throws IOException {
    events.status("Autenticazione con l'orologio");
    byte[] privateKey = new byte[24], shared = null, remote = null;
    new SecureRandom().nextBytes(privateKey);
    try {
      byte[] pub = ECDH_B163.ecdh_generate_public(privateKey);
      Wire.require(pub != null, "Impossibile preparare autenticazione");
      sendService(130, Wire.buffer(52).put(new byte[] {4, 2, 0, 2}).put(pub).array(), false);
      byte[] response = waitService(130);
      Wire.require(
          response.length >= 67 && response[0] == 0x10 && response[1] == 4 && response[2] == 1,
          "Autenticazione iniziale rifiutata");
      remote = Arrays.copyOfRange(response, 3, 19);
      shared = ECDH_B163.ecdh_generate_shared(privateKey, Arrays.copyOfRange(response, 19, 67));
      Arrays.fill(response, (byte) 0);
      Wire.require(shared != null && shared.length >= 24, "Chiave remota non valida");
      codec.sequence = Wire.le(shared).getInt();
      codec.key = new byte[16];
      for (int i = 0; i < 16; i++) codec.key[i] = (byte) (shared[i + 8] ^ authKey[i]);
      byte[] proof =
          Wire.buffer(33)
              .put((byte) 5)
              .put(Wire.aes(remote, authKey, true))
              .put(Wire.aes(remote, codec.key, true))
              .array();
      try {
        sendService(130, proof, false);
      } finally {
        Arrays.fill(proof, (byte) 0);
      }
      response = waitService(130);
      Wire.require(
          response.length >= 3 && response[0] == 0x10 && response[1] == 5 && response[2] == 1,
          "Autenticazione rifiutata: controlla la chiave e che Zepp non occupi la connessione");
    } finally {
      Arrays.fill(privateKey, (byte) 0);
      if (shared != null) Arrays.fill(shared, (byte) 0);
      if (remote != null) Arrays.fill(remote, (byte) 0);
    }
  }

  public void upload(byte[] mp3, String title, String artist) throws IOException {
    Wire.require(ready && !closed, "Verifica prima collegamento e servizio music");
    Wire.require(
        mp3.length > 0 && mp3.length <= 32 * 1024 * 1024,
        "Il prototipo accetta file fino a 32 MiB");
    validateMetadata(title);
    validateMetadata(artist);
    Wire.require(title.length() > 0, "Titolo obbligatorio");
    // Deliberately no speculative URL escaping: reject protocol separators in this prototype.
    // The installed Zepp music flow supplies a space for an absent artist.
    byte[] url = Wire.text("music://file?songName=" + title + "&singer="
        + (artist.isEmpty() ? " " : artist) + "&end=1");
    byte[] name = Wire.text("syncbeat-test.mp3");
    ByteBuffer request = Wire.buffer(2 + url.length + name.length + 10);
    request
        .put((byte) 3)
        .put((byte) 0)
        .put(url)
        .put(name)
        .putInt(mp3.length)
        .putInt(Wire.crc32(mp3))
        .put((byte) 0)
        .put((byte) 0);
    sendService(13, request.array(), services.get(13));
    int offset = parseUploadResponse(waitService(13));
    Wire.require(
        offset >= 0 && offset < mp3.length, "Offset ripresa non supportato: nessun dato inviato");
    // Avoid unsafe resume across sessions: first prototype intentionally starts at zero only.
    Wire.require(offset == 0, "Trasferimento parziale preesistente: ripresa non ancora verificata");
    int index = 0, progress = 0;
    while (progress < mp3.length) {
      int n = Math.min(chunkSize, mp3.length - progress);
      int flags = (progress == 0 ? 1 : 0) | (progress + n == mp3.length ? 2 : 0);
      byte[] chunk =
          Wire.buffer(n + 5)
              .put((byte) 0x12)
              .put((byte) flags)
              .put((byte) index)
              .putShort((short) n)
              .put(mp3, progress, n)
              .array();
      int part = Math.min(codec.mtu - 3, 65531);
      for (int p = 0; p < chunk.length; p += part)
        writeChannel(FILE_SEND, Arrays.copyOfRange(chunk, p, Math.min(p + part, chunk.length)));
      byte[] ack = waitCharacteristic(FILE_SEND);
      Wire.require(
          ack.length >= 4 && ack[0] == 0x13 && ack[1] == 0 && Wire.u(ack[2]) == index,
          "Conferma blocco errata: trasferimento interrotto");
      progress += n;
      index = (index + 1) & 255;
      events.progress(progress, mp3.length);
    }
    ready = false; // Exactly one file per explicit connection; reconnect deliberately for the next.
    events.status(
        "Ultimo blocco confermato. Controlla adesso titolo e riproduzione nel lettore Musica"
            + " dell'orologio: non sono verificabili da qui.");
  }

  // Response format from Gadgetbridge ZeppOsFileTransferV3: command, session,
  // status, uint32 existing progress. Never include raw payloads or credentials.
  static int parseUploadResponse(byte[] response) throws IOException {
    Wire.require(response.length >= 3, "Risposta importazione incompleta (intestazione)");
    ByteBuffer b = Wire.le(response);
    int command = Wire.u(b.get()), transferSession = Wire.u(b.get()), status = Wire.u(b.get());
    Wire.require(command == 4, "Risposta importazione inattesa (comando " + command + ")");
    Wire.require(transferSession == 0, "Sessione importazione inattesa (" + transferSession + ")");
    Wire.require(status == 0,
        "Importazione rifiutata dall'orologio (codice " + status
            + "). Nessun blocco audio inviato.");
    Wire.require(b.remaining() >= 4, "Risposta importazione incompleta (avanzamento)");
    return b.getInt();
  }

  public static void validateMetadata(String s) throws IOException {
    Wire.require(
        s != null && s.getBytes(StandardCharsets.UTF_8).length <= 31,
        "Metadati troppo lunghi (massimo 31 byte)");
    for (char c : s.toCharArray())
      Wire.require(
          c >= 32 && c != 127 && "&?#%=".indexOf(c) < 0,
          "Per questa prova evita caratteri di controllo o & ? # % = nei metadati");
  }

  private void send(int command, byte[] data) throws IOException {
    Wire.require(!closed, "Connessione chiusa");
    out.write(Wire.frame(command, sequence++ & 255, data));
    out.flush();
  }

  private Wire.Packet waitCommand(int cmd) throws IOException {
    for (int i = 0; i < 1024; i++) {
      Wire.Packet p = Wire.read(in);
      if (p.command == cmd) return p;
      if (p.command == 5) throw new IOException("L'orologio ha chiuso la sessione");
    }
    throw new IOException("Risposta Classic inattesa");
  }

  private void writeChannel(String uuid, byte[] data) throws IOException {
    Integer channel = channels.get(uuid);
    Wire.require(channel != null, "Canale non disponibile");
    send(
        7,
        Wire.buffer(data.length + 4)
            .put((byte) session)
            .putShort(channel.shortValue())
            .put((byte) 0)
            .put(data)
            .array());
  }

  private void sendService(int endpoint, byte[] data, boolean encrypted) throws IOException {
    codec.send(endpoint, data, encrypted, bytes -> writeChannel(WRITE, bytes));
  }

  private byte[] waitCharacteristic(String wanted) throws IOException {
    for (int i = 0; i < 2048; i++) {
      Wire.Packet p = Wire.read(in);
      if (p.command == 5) throw new IOException("L'orologio ha chiuso la sessione");
      if (p.command == 9) {
        send(10, new byte[] {(byte) session, 1, 0, 0});
        continue;
      }
      if (p.command != 7) continue;
      ByteBuffer b = Wire.le(p.payload);
      Wire.require(b.remaining() >= 4, "Canale incompleto");
      Wire.require(Wire.u(b.get()) == session, "Sessione Bluetooth cambiata");
      int channel = b.getShort() & 65535, ack = Wire.u(b.get());
      byte[] data = Wire.bytes(b, b.remaining());
      if (ack != 0) send(8, new byte[] {(byte) session, (byte) p.sequence, 1, 0});
      if (Objects.equals(channels.get(wanted), channel)) return data;
      // V3 replies are only accepted on their mapped channel; unsolicited service frames are
      // ignored here.
    }
    throw new IOException("Nessuna risposta sul canale richiesto");
  }

  private byte[] waitService(int endpoint) throws IOException {
    for (int i = 0; i < 512; i++) {
      byte[] data = waitCharacteristic(READ);
      if (data.length > 0 && data[0] == 4) continue;
      ChunkCodec.Message message = codec.accept(data);
      if (codec.needsAck)
        writeChannel(READ, new byte[] {4, 0, (byte) codec.ackHandle, 1, (byte) codec.ackCount});
      if (message != null && message.endpoint == endpoint) return message.payload;
    }
    throw new IOException("Servizio senza risposta");
  }

  public void close() {
    closed = true;
    ready = false;
    codec.close();
    try {
      in.close();
    } catch (IOException ignored) {
    }
    try {
      out.close();
    } catch (IOException ignored) {
    }
  }
}
