/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Flusso di riferimento Zepp OS su Bluetooth Classic, scritto per confronto.
 * Framing pacchetti: [0x55, cmd, seq, len u16 LE, payload, crc16 u16 LE, 0xaa],
 * crc16 calcolato su cmd+seq+len+payload.
 * Fonti (verificate il 2026-11-17):
 *  - Gadgetbridge ZeppOsBtbrSupport.java, metodi write() e crc16() e costanti CMD_*:
 *    https://codeberg.org/Freeyourgadget/Gadgetbridge/raw/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/huami/zeppos/ZeppOsBtbrSupport.java
 *  - OronBox lib/src/device/zeppos/zeppos_btbr_transport.dart, _sendFrame/_onRawData:
 *    https://github.com/zxor-org/OronBox (AGPL-3.0 + ADDITIONAL-TERMS, attribuzione in docs)
 * Scritto ex novo da quelle fonti; non copiato dal codice SyncBeat esistente.
 */
package com.example.syncbeat.zeppref;

import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.zip.CRC32;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

final class RefWire {
  static final int PREAMBLE = 0x55;
  static final int TRAILER = 0xaa;

  // Comandi del livello di trasporto Classic (GB ZeppOsBtbrSupport righe 76-85,
  // OronBox zeppos_btbr_transport.dart righe 29-38).
  static final int CMD_CHANNELS_GET = 0x01;
  static final int CMD_CHANNELS_RET = 0x02;
  static final int CMD_SESSION_START = 0x03;
  static final int CMD_SESSION_START_ACK = 0x04;
  static final int CMD_SESSION_END = 0x05;
  static final int CMD_CHANNEL_DATA = 0x07;
  static final int CMD_CHANNEL_ACK = 0x08;
  static final int CMD_PING = 0x09;
  static final int CMD_PONG = 0x0a;

  private RefWire() {}

  static ByteBuffer le(int size) {
    return ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN);
  }

  static void require(boolean ok, String message) throws IOException {
    if (!ok) throw new IOException(message);
  }

  static int u(byte b) {
    return b & 0xff;
  }

  static int crc16(byte[] data, int off, int len) {
    // Stessa variante CRC-16 dei due riferimenti (polinomio riflesso, init 0xffff).
    int crc = 0xffff;
    for (int i = off; i < off + len; i++) {
      crc = ((crc >>> 8) | (crc << 8)) & 0xffff;
      crc ^= u(data[i]);
      crc ^= (crc & 0xff) >> 4;
      crc ^= (crc << 12) & 0xffff;
      crc ^= ((crc & 0xff) << 5) & 0xffff;
    }
    return crc & 0xffff;
  }

  static int crc32(byte[] data) {
    CRC32 crc = new CRC32();
    crc.update(data);
    return (int) crc.getValue();
  }

  /** Stringa NUL-terminata dentro il buffer (tabella canali, richiesta upload). */
  static String cstring(ByteBuffer b, int max) throws IOException {
    StringBuilder out = new StringBuilder();
    while (b.hasRemaining()) {
      byte v = b.get();
      if (v == 0) return out.toString();
      require(out.length() < max, "REF: stringa senza terminatore entro il limite");
      out.append((char) u(v));
    }
    throw new IOException("REF: stringa senza terminatore");
  }

  static byte[] utf8z(String value) {
    return (value + "\0").getBytes(StandardCharsets.UTF_8);
  }

  /** AES-128-ECB senza padding, richiesto dal protocollo (autenticazione e messaggi cifrati). */
  @android.annotation.SuppressLint("GetInstance")
  static byte[] aesEcb(byte[] data, byte[] key, boolean encrypt) throws IOException {
    try {
      Cipher cipher = Cipher.getInstance("AES/ECB/NoPadding");
      cipher.init(encrypt ? Cipher.ENCRYPT_MODE : Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"));
      return cipher.doFinal(data);
    } catch (GeneralSecurityException e) {
      throw new IOException("REF: AES non disponibile", e);
    }
  }

  static final class Packet {
    final int command;
    final int sequence;
    final byte[] payload;

    Packet(int command, int sequence, byte[] payload) {
      this.command = command;
      this.sequence = sequence;
      this.payload = payload;
    }
  }

  /** Scrive un frame completo e fa flush (OronBox _sendFrame, GB write()). */
  static void writeFrame(OutputStream out, int command, int sequence, byte[] payload)
      throws IOException {
    require(payload.length <= 0xffff, "REF: payload oltre 65535 byte");
    ByteBuffer body = le(payload.length + 4);
    body.put((byte) command).put((byte) sequence).putShort((short) payload.length).put(payload);
    byte[] b = body.array();
    ByteBuffer frame = le(b.length + 4);
    frame.put((byte) PREAMBLE).put(b).putShort((short) crc16(b, 0, b.length)).put((byte) TRAILER);
    out.write(frame.array());
    out.flush();
  }

  /** Legge un frame dallo stream; fallisce rumorosamente se il CRC non torna. */
  static Packet readFrame(InputStream in) throws IOException {
    int preamble = readByte(in);
    require(preamble == PREAMBLE, "REF: preambolo frame atteso 0x55, trovato 0x" + Integer.toHexString(preamble));
    int command = readByte(in);
    int sequence = readByte(in);
    int lenLo = readByte(in);
    int lenHi = readByte(in);
    int length = lenLo | (lenHi << 8);
    byte[] payload = readFully(in, length);
    int crcLo = readByte(in);
    int crcHi = readByte(in);
    int expected = crcLo | (crcHi << 8);
    require(readByte(in) == TRAILER, "REF: terminatore frame mancante");
    ByteBuffer body = le(4);
    body.put((byte) command).put((byte) sequence).putShort((short) length);
    byte[] head = body.array();
    byte[] joined = new byte[head.length + payload.length];
    System.arraycopy(head, 0, joined, 0, head.length);
    System.arraycopy(payload, 0, joined, head.length, payload.length);
    int actual = crc16(joined, 0, joined.length);
    require(actual == expected, "REF: CRC frame non valido sul comando " + command);
    return new Packet(command, sequence, payload);
  }

  private static int readByte(InputStream in) throws IOException {
    int v = in.read();
    if (v < 0) throw new EOFException("REF: stream chiuso dall'orologio");
    return v;
  }

  private static byte[] readFully(InputStream in, int length) throws IOException {
    byte[] out = new byte[length];
    int off = 0;
    while (off < length) {
      int n = in.read(out, off, length - off);
      if (n < 0) throw new EOFException("REF: stream chiuso dentro un frame");
      off += n;
    }
    return out;
  }
}
