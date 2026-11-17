/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Flusso di riferimento Zepp OS su Bluetooth Classic per confronto con il flusso
 * principale di SyncBeat. Obiettivo: stesse fasi, stessi byte dei due riferimenti
 * pubblici, con diagnostica esplicita per fase (tempi, MTU, chunkSize, ack),
 * cosi' sul dispositivo si vede dove i due flussi divergono.
 *
 * Fonti (verificate il 2026-11-17):
 *  - OronBox: lib/src/device/zeppos/zeppos_btbr_transport.dart (sessione, canali,
 *    ping/pong, frame canale con requestAck=0), zeppos_device_component.dart
 *    (codec endpoint), systems/zeppos_auth_system.dart (autenticazione ECDH su
 *    endpoint 130), systems/zeppos_music_upload_system.dart (richiesta music://,
 *    layout identico a Gadgetbridge), systems/zeppos_v3_file_transfer.dart
 *    (chunk 0x12, ack 0x13, parti grandi quanto l'MTU di sessione senza clamp).
 *    Repo: https://github.com/zxor-org/OronBox (AGPL-3.0 + ADDITIONAL-TERMS;
 *    attribuzione gia' in docs/zepp-musica.it.md).
 *  - Gadgetbridge: service/devices/huami/zeppos/ZeppOsBtbrSupport.java,
 *    ZeppOsSupport.java, services/filetransfer/ZeppOsFileTransferV3.java.
 *    https://codeberg.org/Freeyourgadget/Gadgetbridge (AGPL-3.0-or-later)
 *
 * Scritto ex novo da quelle fonti. Nessun retry automatico, nessun fallback,
 * nessun removeBond: un solo tentativo per chiamata, come da limiti del progetto.
 * NON testato su hardware: la verifica spetta ad Antonio confrontandolo con il
 * suo flusso. Niente qui prova che il protocollo sia "quello giusto" sul suo
 * modello/firmware: e' una base di confronto, non una correzione.
 */
package com.example.syncbeat.zeppref;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import com.example.syncbeat.zepp.ECDH_B163;

public final class RefFlow implements AutoCloseable {
  // UUID dei servizi Classic (GB HuamiService / OronBox device_profile).
  public static final String SERIAL_UUID = "00000022-0000-3512-2118-0009af100700";
  static final String CHUNKED_WRITE = "00000016-0000-3512-2118-0009af100700";
  static final String CHUNKED_READ = "00000017-0000-3512-2118-0009af100700";
  static final String FILE_SEND = "00000023-0000-3512-2118-0009af100700";

  static final int ENDPOINT_AUTH = 130;
  static final int ENDPOINT_SERVICES = 0;
  static final int ENDPOINT_FILE_TRANSFER = 13;

  public interface Events {
    void phase(String text);
    void progress(int done, int total);
  }

  private final InputStream in;
  private final OutputStream out;
  private final Events events;
  private final RefChunked codec = new RefChunked();
  private final Map<String, Integer> channels = new HashMap<>();
  private final Map<Integer, Boolean> endpoints = new HashMap<>();
  private int txSequence;
  private int session = -1;
  private int sessionMtu;
  private int chunkSize;
  private boolean closed;
  private long startedAt;

  public RefFlow(InputStream in, OutputStream out, Events events) {
    this.in = in;
    this.out = out;
    this.events = events;
  }

  /** Fasi 1-5: canali, sessione, autenticazione, servizi, capacita'. */
  public void initialize(byte[] authKey) throws IOException {
    RefWire.require(authKey.length == 16 && session < 0 && !closed, "REF: stato iniziale non valido");
    startedAt = System.currentTimeMillis();
    negotiateChannels();
    startSession();
    authenticate(authKey);
    fetchServices();
    fetchCapabilities();
  }

  /** Fase 1: tabella canali (cmd 1 -> cmd 2). OronBox _handleChannelsResponse. */
  private void negotiateChannels() throws IOException {
    long t = phase("1/8 Tabella canali Classic richiesta");
    send(RefWire.CMD_CHANNELS_GET, new byte[0]);
    RefWire.Packet p = waitCommand(RefWire.CMD_CHANNELS_RET, "tabella canali");
    ByteBuffer b = RefWire.le(p.payload.length).put(p.payload);
    b.flip();
    RefWire.require(b.remaining() >= 3 && RefWire.u(b.get()) <= 1, "REF: versione tabella canali non supportata");
    int count = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
    RefWire.require(count <= 128, "REF: troppi canali nella tabella");
    for (int i = 0; i < count; i++) {
      String uuid;
      try {
        uuid = UUID.fromString(RefWire.cstring(b, 64)).toString();
      } catch (IllegalArgumentException e) {
        throw new IOException("REF: UUID canale non valido");
      }
      RefWire.require(b.remaining() >= 2, "REF: voce canale incompleta");
      channels.put(uuid, RefWire.u(b.get()) | (RefWire.u(b.get()) << 8));
    }
    RefWire.require(
        channels.containsKey(CHUNKED_WRITE) && channels.containsKey(CHUNKED_READ),
        "REF: canali endpoint Zepp OS mancanti");
    done("1/8", t, channels.size() + " canali");
  }

  /** Fase 2: avvio sessione con nonce (cmd 3 -> cmd 4). OronBox riga 308-337. */
  private void startSession() throws IOException {
    long t = phase("2/8 Avvio sessione Classic");
    int nonce = new SecureRandom().nextInt();
    send(RefWire.CMD_SESSION_START, RefWire.le(4).putInt(nonce).array());
    ByteBuffer b = payloadOf(waitCommand(RefWire.CMD_SESSION_START_ACK, "avvio sessione"));
    RefWire.require(b.remaining() >= 8 && b.getInt() == nonce, "REF: nonce di sessione non corrisposto");
    RefWire.require(RefWire.u(b.get()) == 1, "REF: sessione rifiutata dall'orologio");
    session = RefWire.u(b.get());
    sessionMtu = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
    RefWire.require(sessionMtu >= 32 && sessionMtu <= 65535, "REF: MTU di sessione non valido");
    codec.maxPacket = sessionMtu;
    done("2/8", t, "sessione=" + session + " mtu=" + sessionMtu);
  }

  /** Fase 3: autenticazione ECDH su endpoint 130. OronBox zeppos_auth_system.dart. */
  private void authenticate(byte[] authKey) throws IOException {
    long t = phase("3/8 Autenticazione con l'orologio");
    byte[] privateKey = new byte[24];
    byte[] shared = null, remoteRandom = null, response = null;
    new SecureRandom().nextBytes(privateKey);
    try {
      byte[] pub = ECDH_B163.ecdh_generate_public(privateKey);
      RefWire.require(pub != null && pub.length == 48, "REF: chiave pubblica ECDH non generata");
      sendEndpoint(ENDPOINT_AUTH, RefWire.le(52).put(new byte[] {4, 2, 0, 2}).put(pub).array(), false);
      response = waitEndpointRaw(ENDPOINT_AUTH, "scambio chiavi");
      RefWire.require(
          response.length >= 67 && response[0] == 0x10 && response[1] == 4 && response[2] == 1,
          "REF: scambio chiavi rifiutato");
      remoteRandom = Arrays.copyOfRange(response, 3, 19);
      shared = ECDH_B163.ecdh_generate_shared(privateKey, Arrays.copyOfRange(response, 19, 67));
      Arrays.fill(response, (byte) 0);
      response = null;
      RefWire.require(shared != null && shared.length >= 24, "REF: segreto condiviso non valido");
      codec.sequence = RefWire.le(4).put(shared, 0, 4).flip().getInt();
      codec.key = new byte[16];
      for (int i = 0; i < 16; i++) codec.key[i] = (byte) (shared[i + 8] ^ authKey[i]);
      byte[] proof = RefWire.le(33)
          .put((byte) 5)
          .put(RefWire.aesEcb(remoteRandom, authKey, true))
          .put(RefWire.aesEcb(remoteRandom, codec.key, true))
          .array();
      try {
        sendEndpoint(ENDPOINT_AUTH, proof, false);
      } finally {
        Arrays.fill(proof, (byte) 0);
      }
      response = waitEndpointRaw(ENDPOINT_AUTH, "prova autenticazione");
      RefWire.require(
          response.length >= 3 && response[0] == 0x10 && response[1] == 5 && response[2] == 1,
          "REF: autenticazione rifiutata (chiave o connessione occupata)");
      done("3/8", t, "endpoint 130 ok");
    } finally {
      Arrays.fill(privateKey, (byte) 0);
      if (shared != null) Arrays.fill(shared, (byte) 0);
      if (remoteRandom != null) Arrays.fill(remoteRandom, (byte) 0);
      if (response != null) Arrays.fill(response, (byte) 0);
    }
  }

  /** Fase 4: lista servizi endpoint 0. OronBox zeppos_services_system. */
  private void fetchServices() throws IOException {
    long t = phase("4/8 Lettura servizi disponibili");
    sendEndpoint(ENDPOINT_SERVICES, new byte[] {3}, false);
    ByteBuffer b = payloadOf(waitEndpointRaw(ENDPOINT_SERVICES, "lista servizi"));
    RefWire.require(b.remaining() >= 3 && RefWire.u(b.get()) == 4, "REF: lista servizi non riconosciuta");
    int count = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
    RefWire.require(count <= 1024 && count * 3 <= b.remaining(), "REF: lista servizi incompleta");
    for (int i = 0; i < count; i++) {
      int endpoint = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
      int enc = RefWire.u(b.get());
      RefWire.require(enc <= 1, "REF: flag cifratura servizio sconosciuto");
      endpoints.put(endpoint, enc == 1);
    }
    RefWire.require(
        endpoints.containsKey(ENDPOINT_FILE_TRANSFER),
        "REF: servizio trasferimento file (13) assente");
    done("4/8", t, endpoints.size() + " servizi, endpoint 13 cifrato=" + endpoints.get(ENDPOINT_FILE_TRANSFER));
  }

  /** Fase 5: capacita' trasferimento V3 su endpoint 13. OronBox _parseSupportedServices. */
  private void fetchCapabilities() throws IOException {
    long t = phase("5/8 Lettura capacita' trasferimento");
    sendEndpoint(ENDPOINT_FILE_TRANSFER, new byte[] {1}, endpoints.get(ENDPOINT_FILE_TRANSFER));
    ByteBuffer b = payloadOf(waitEndpointRaw(ENDPOINT_FILE_TRANSFER, "capacita' trasferimento"));
    RefWire.require(b.remaining() >= 10 && RefWire.u(b.get()) == 2, "REF: risposta capacita' non riconosciuta");
    RefWire.require(RefWire.u(b.get()) == 3, "REF: accettato solo file transfer V3");
    chunkSize = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
    b.getInt(); // chunkSize per file compressi, non usato qui
    int count = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
    RefWire.require(chunkSize > 0 && count <= 256, "REF: capacita' trasferimento non valide");
    boolean music = false;
    for (int i = 0; i < count; i++) if (RefWire.cstring(b, 128).equals("music")) music = true;
    RefWire.require(music, "REF: servizio music non dichiarato dall'orologio");
    RefWire.require(channels.containsKey(FILE_SEND), "REF: canale FILE_SEND assente");
    done("5/8", t, "V3 chunkSize=" + chunkSize + " music=si'");
  }

  /**
   * Fasi 6-8: richiesta upload, dati a chunk 0x12 con ack 0x13, chiusura logica.
   * OronBox zeppos_music_upload_system.dart + zeppos_v3_file_transfer.dart;
   * Gadgetbridge ZeppOsFileTransferV3.java.
   */
  public void upload(byte[] mp3, String title, String artist) throws IOException {
    RefWire.require(session >= 0 && !closed, "REF: initialize non completato");
    RefWire.require(mp3.length > 0, "REF: file vuoto");
    long t = phase("6/8 Richiesta upload (" + mp3.length + " byte)");
    byte[] url = RefWire.utf8z("music://file?songName=" + title + "&singer=" + artist + "&end=1");
    byte[] name = RefWire.utf8z("syncbeat-test.mp3");
    ByteBuffer request = RefWire.le(2 + url.length + name.length + 10)
        .put((byte) 3)
        .put((byte) 0) // sessione di trasferimento: sempre 0 in questo flusso
        .put(url)
        .put(name)
        .putInt(mp3.length)
        .putInt(RefWire.crc32(mp3))
        .put((byte) 0)
        .put((byte) 0);
    sendEndpoint(ENDPOINT_FILE_TRANSFER, request.array(), endpoints.get(ENDPOINT_FILE_TRANSFER));
    ByteBuffer b = payloadOf(waitEndpointRaw(ENDPOINT_FILE_TRANSFER, "accettazione upload"));
    RefWire.require(
        b.remaining() >= 7 && RefWire.u(b.get()) == 4 && b.get() == 0 && b.get() == 0,
        "REF: upload rifiutato dall'orologio");
    int offset = b.getInt();
    RefWire.require(offset == 0, "REF: ripresa da offset " + offset + " non gestita in questo flusso");
    done("6/8", t, "accettato, offset=0");

    t = phase("7/8 Invio dati (" + chunkSize + " byte/chunk, parti da " + sessionMtu + ")");
    int index = 0, progress = 0;
    while (progress < mp3.length) {
      int n = Math.min(chunkSize, mp3.length - progress);
      int flags = (progress == 0 ? 1 : 0) | (progress + n == mp3.length ? 2 : 0);
      ByteBuffer chunk = RefWire.le(n + 5)
          .put((byte) 0x12)
          .put((byte) flags)
          .put((byte) index)
          .putShort((short) n);
      chunk.put(mp3, progress, n);
      byte[] packet = chunk.array();
      long chunkStart = System.currentTimeMillis();
      // Parti grandi quanto l'MTU di sessione, senza clamp: come OronBox
      // (zeppos_v3_file_transfer.dart righe 84-95 + btbr_transport riga 75).
      for (int p = 0; p < packet.length; p += sessionMtu) {
        writeChannel(FILE_SEND, Arrays.copyOfRange(packet, p, Math.min(p + sessionMtu, packet.length)));
      }
      byte[] ack = waitChannelData(FILE_SEND, "ack chunk " + index);
      RefWire.require(
          ack.length >= 3 && RefWire.u(ack[0]) == 0x13 && ack[1] == 0 && RefWire.u(ack[2]) == (index & 0xff),
          "REF: ack chunk " + index + " errato o negativo");
      progress += n;
      events.progress(progress, mp3.length);
      events.phase("7/8 chunk " + index + " confermato in "
          + (System.currentTimeMillis() - chunkStart) + " ms (" + progress + "/" + mp3.length + ")");
      index = (index + 1) & 0xff;
    }
    done("7/8", t, mp3.length + " byte inviati e confermati");
    events.phase("8/8 Trasferimento completato in " + (System.currentTimeMillis() - startedAt)
        + " ms. Titolo e riproduzione nel lettore Musica non sono verificabili da qui.");
  }

  // ---- livello trasporto ----

  private void send(int command, byte[] payload) throws IOException {
    RefWire.require(!closed, "REF: flusso chiuso");
    RefWire.writeFrame(out, command, txSequence++ & 0xff, payload);
  }

  /** Frame canale: [sessione, canale u16 LE, requestAck=0, dati]. Entrambi i riferimenti usano ack=0. */
  private void writeChannel(String uuid, byte[] data) throws IOException {
    Integer channel = channels.get(uuid);
    RefWire.require(channel != null, "REF: canale non disponibile per " + uuid);
    ByteBuffer b = RefWire.le(data.length + 4)
        .put((byte) session)
        .putShort(channel.shortValue())
        .put((byte) 0);
    b.put(data);
    send(RefWire.CMD_CHANNEL_DATA, b.array());
  }

  private void sendEndpoint(int endpoint, byte[] data, boolean encrypt) throws IOException {
    codec.send(endpoint, data, encrypt, bytes -> writeChannel(CHUNKED_WRITE, bytes));
  }

  /** Attende un comando di trasporto, rispondendo ai ping (OronBox _handlePing riga 378). */
  private RefWire.Packet waitCommand(int wanted, String what) throws IOException {
    for (int i = 0; i < 1024; i++) {
      RefWire.Packet p = RefWire.readFrame(in);
      if (p.command == RefWire.CMD_PING) {
        handlePing(p.payload);
        continue;
      }
      if (p.command == RefWire.CMD_SESSION_END) {
        throw new IOException("REF: orologio ha chiuso la sessione durante " + what);
      }
      if (p.command == wanted) return p;
    }
    throw new IOException("REF: attesa esaurita per " + what);
  }

  private void handlePing(byte[] payload) throws IOException {
    if (payload.length > 0 && RefWire.u(payload[0]) == session) {
      send(RefWire.CMD_PONG, new byte[] {(byte) session, 1, 0, 0});
    }
  }

  /** Dati grezzi su un canale specifico (ack di trasporto quando richiesti). */
  private byte[] waitChannelData(String uuid, String what) throws IOException {
    Integer wanted = channels.get(uuid);
    for (int i = 0; i < 2048; i++) {
      RefWire.Packet p = RefWire.readFrame(in);
      if (p.command == RefWire.CMD_PING) {
        handlePing(p.payload);
        continue;
      }
      if (p.command == RefWire.CMD_SESSION_END) {
        throw new IOException("REF: orologio ha chiuso la sessione durante " + what);
      }
      if (p.command != RefWire.CMD_CHANNEL_DATA) continue;
      ByteBuffer b = payloadOf(p);
      RefWire.require(b.remaining() >= 4, "REF: frame canale incompleto");
      RefWire.require(RefWire.u(b.get()) == session, "REF: numero sessione cambiato");
      int channel = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
      int ackRequest = RefWire.u(b.get());
      byte[] data = new byte[b.remaining()];
      b.get(data);
      if (ackRequest != 0) {
        send(RefWire.CMD_CHANNEL_ACK, new byte[] {(byte) session, (byte) p.sequence, 1, 0});
      }
      if (Objects.equals(wanted, channel)) return data;
    }
    throw new IOException("REF: nessun dato sul canale per " + what);
  }

  /** Messaggio endpoint completo (riassemblato dal codec) sul canale READ. */
  private byte[] waitEndpointRaw(int endpoint, String what) throws IOException {
    for (int i = 0; i < 512; i++) {
      byte[] data = waitChannelData(CHUNKED_READ, what);
      if (data.length > 0 && data[0] == 4) continue; // ack del codec, non un messaggio
      RefChunked.Message message = codec.accept(data);
      if (codec.ackPending) {
        writeChannel(CHUNKED_READ, new byte[] {4, 0, (byte) codec.ackHandle, 1, (byte) codec.ackCount});
      }
      if (message != null) {
        RefWire.require(message.endpoint == endpoint, "REF: endpoint inatteso " + message.endpoint);
        return message.payload;
      }
    }
    throw new IOException("REF: servizio senza risposta per " + what);
  }

  private static ByteBuffer payloadOf(RefWire.Packet p) {
    return payloadOf(p.payload);
  }

  private static ByteBuffer payloadOf(byte[] payload) {
    ByteBuffer b = RefWire.le(payload.length).put(payload);
    b.flip();
    return b;
  }

  private long phase(String text) {
    events.phase(text);
    return System.currentTimeMillis();
  }

  private void done(String step, long started, String detail) {
    events.phase(step + " ok in " + (System.currentTimeMillis() - started) + " ms - " + detail);
  }

  @Override
  public void close() {
    closed = true;
    codec.clearKey();
  }
}
