/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Codec dei messaggi "chunked" (endpoint numerici) del flusso di riferimento.
 * Ogni messaggio: pacchetti [0x03, flags, 0x00, handle, count, ...]; il primo
 * pacchetto aggiunge [plainLength u32 LE, endpoint u16 LE] (header 11 byte, gli
 * altri 5). flags: first 0x01, last 0x02, needsAck 0x04, encrypted 0x08.
 * Dimensione pacchetto limitata a clamp(maxWriteLength, 20, 512).
 * Cifratura: payload + seq u32 LE + crc32(payload+seq), padding a 16, AES-128-ECB
 * con chiave = chiaveSessione XOR handle.
 * Fonte: OronBox lib/src/device/zeppos/zeppos_device_component.dart
 * (sendToEndpoint, _maxChunkPayload righe 226-229, _sendAck riga 184, flag righe 22-27),
 * con lo stesso schema di Gadgetbridge Huami2021ChunkedEncoder/Decoder.
 */
package com.example.syncbeat.zeppref;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.Arrays;

final class RefChunked {
  interface Sink {
    void send(byte[] packet) throws IOException;
  }

  static final class Message {
    final int endpoint;
    final byte[] payload;

    Message(int endpoint, byte[] payload) {
      this.endpoint = endpoint;
      this.payload = payload;
    }
  }

  byte[] key; // chiave di sessione a 16 byte, nulla finche' non autenticati
  int sequence; // contatore dei messaggi cifrati in uscita
  int writeHandle;
  int maxPacket = 247; // aggiornato con l'MTU di sessione, poi clampato 20..512

  // Stato di riassemblaggio in ingresso.
  private int inHandle = -1, inCount, inEndpoint, inPlainLength;
  private boolean inEncrypted;
  private ByteBuffer inBuffer;
  boolean ackPending;
  int ackHandle, ackCount;

  private int packetLimit() {
    return Math.max(20, Math.min(512, maxPacket));
  }

  /** Codifica e invia un messaggio endpoint (OronBox sendToEndpoint). */
  void send(int endpoint, byte[] data, boolean encrypt, Sink sink) throws IOException {
    RefWire.require(data.length > 0 && data.length <= 65536, "REF: messaggio endpoint non valido");
    RefWire.require(!encrypt || key != null, "REF: endpoint cifrato prima dell'autenticazione");
    writeHandle = (writeHandle + 1) & 0xff;
    byte[] outgoing = data;
    if (encrypt) {
      byte[] messageKey = new byte[16];
      for (int i = 0; i < 16; i++) messageKey[i] = (byte) (key[i] ^ (byte) writeHandle);
      int length = (data.length + 8 + 15) / 16 * 16;
      ByteBuffer b = RefWire.le(length).put(data).putInt(sequence++);
      b.putInt(RefWire.crc32(Arrays.copyOf(b.array(), data.length + 4)));
      try {
        outgoing = RefWire.aesEcb(b.array(), messageKey, true);
      } finally {
        Arrays.fill(messageKey, (byte) 0);
      }
    }
    int position = 0, count = 0;
    while (position < outgoing.length) {
      int header = position == 0 ? 11 : 5;
      int length = Math.min(outgoing.length - position, packetLimit() - header);
      RefWire.require(length > 0 && count <= 255, "REF: pacchetto endpoint troppo piccolo");
      boolean last = position + length == outgoing.length;
      ByteBuffer p = RefWire.le(header + length);
      int flags = (position == 0 ? 0x01 : 0) | (last ? 0x02 | 0x04 : 0) | (encrypt ? 0x08 : 0);
      p.put((byte) 0x03).put((byte) flags).put((byte) 0).put((byte) writeHandle).put((byte) count++);
      if (position == 0) p.putInt(data.length).putShort((short) endpoint);
      p.put(outgoing, position, length);
      sink.send(p.array());
      position += length;
    }
    if (encrypt) Arrays.fill(outgoing, (byte) 0);
  }

  /**
   * Accetta un pacchetto in arrivo sul canale READ. Ritorna il messaggio completo
   * oppure null se serve un altro pacchetto. Se il pacchetto chiedeva ack,
   * ackPending e' vero e chi chiama deve rispondere [0x04,0,handle,1,count]
   * (OronBox _sendAck riga 184).
   */
  Message accept(byte[] packet) throws IOException {
    ackPending = false;
    RefWire.require(packet.length >= 5, "REF: pacchetto endpoint corto");
    ByteBuffer b = RefWire.le(packet.length).put(packet);
    b.flip();
    RefWire.require(RefWire.u(b.get()) == 0x03, "REF: pacchetto endpoint sconosciuto");
    int flags = RefWire.u(b.get());
    b.get(); // byte esteso, sempre 0 nei riferimenti
    int handle = RefWire.u(b.get());
    int count = RefWire.u(b.get());
    if ((flags & 0x04) != 0) {
      ackPending = true;
      ackHandle = handle;
      ackCount = count;
    }
    if ((flags & 0x01) != 0) {
      RefWire.require(inHandle < 0 && count == 0 && b.remaining() >= 6, "REF: inizio messaggio inatteso");
      inPlainLength = b.getInt();
      inEndpoint = RefWire.u(b.get()) | (RefWire.u(b.get()) << 8);
      inEncrypted = (flags & 0x08) != 0;
      RefWire.require(inPlainLength > 0 && inPlainLength <= 65536, "REF: lunghezza messaggio non valida");
      int stored = inEncrypted ? (inPlainLength + 8 + 15) / 16 * 16 : inPlainLength;
      inBuffer = RefWire.le(stored);
      inHandle = handle;
      inCount = 0;
    }
    RefWire.require(
        inBuffer != null && inHandle == handle && count == (inCount & 0xff),
        "REF: sequenza pacchetti non valida");
    RefWire.require(
        ((flags & 0x08) != 0) == inEncrypted && b.remaining() <= inBuffer.remaining(),
        "REF: pacchetto oltre i limiti");
    inBuffer.put(packet, 5 + ((flags & 0x01) != 0 ? 6 : 0), b.remaining());
    inCount++;
    if ((flags & 0x02) == 0) return null;
    RefWire.require(!inBuffer.hasRemaining(), "REF: messaggio troncato");
    byte[] raw = inBuffer.array();
    byte[] out = raw;
    if (inEncrypted) {
      RefWire.require(key != null, "REF: risposta cifrata prima dell'autenticazione");
      byte[] messageKey = new byte[16];
      for (int i = 0; i < 16; i++) messageKey[i] = (byte) (key[i] ^ (byte) inHandle);
      try {
        out = RefWire.aesEcb(raw, messageKey, false);
      } finally {
        Arrays.fill(messageKey, (byte) 0);
      }
      int crcAt = inPlainLength + 4;
      int expected =
          RefWire.u(out[crcAt])
              | (RefWire.u(out[crcAt + 1]) << 8)
              | (RefWire.u(out[crcAt + 2]) << 16)
              | (RefWire.u(out[crcAt + 3]) << 24);
      int actual = RefWire.crc32(Arrays.copyOf(out, inPlainLength + 4));
      RefWire.require(actual == expected, "REF: CRC messaggio cifrato non valido");
    }
    byte[] result = Arrays.copyOf(out, inPlainLength);
    Arrays.fill(raw, (byte) 0);
    if (out != raw) Arrays.fill(out, (byte) 0);
    inBuffer = null;
    inHandle = -1;
    return new Message(inEndpoint, result);
  }

  void clearKey() {
    if (key != null) Arrays.fill(key, (byte) 0);
    key = null;
  }
}
