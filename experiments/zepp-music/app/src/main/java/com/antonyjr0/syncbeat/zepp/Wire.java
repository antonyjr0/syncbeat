/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Adapted 2026-11-16 from Gadgetbridge ZeppOsBtbrSupport (C) 2025-2026 José Rebelo.
 * CRC routine from CheckSums: Copyright (C) 2015-2025 Andreas Shimokawa,
 * Carsten Pfeiffer, Damien Gaignon, Daniele Gobbetti, José Rebelo, Petr Vaněk, vappster.
 * See THIRD_PARTY_NOTICES.md for source revision and changes. */
package com.antonyjr0.syncbeat.zepp;

import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.CRC32;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

final class Wire {
  static ByteBuffer le(byte[] bytes) {
    return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
  }

  static ByteBuffer buffer(int size) {
    return ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN);
  }

  static int u(byte b) {
    return b & 255;
  }

  static void require(boolean ok, String message) throws IOException {
    if (!ok) throw new IOException(message);
  }

  static byte[] bytes(ByteBuffer b, int size) throws IOException {
    require(size >= 0 && size <= b.remaining(), "Risposta incompleta");
    byte[] out = new byte[size];
    b.get(out);
    return out;
  }

  static String string(ByteBuffer b, int max) throws IOException {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    while (b.hasRemaining()) {
      byte v = b.get();
      if (v == 0) return new String(out.toByteArray(), StandardCharsets.UTF_8);
      require(out.size() < max, "Testo troppo lungo nella risposta");
      out.write(v);
    }
    throw new IOException("Risposta senza terminatore");
  }

  static byte[] text(String value) {
    return (value + "\0").getBytes(StandardCharsets.UTF_8);
  }

  static int crc32(byte[] data) {
    CRC32 crc = new CRC32();
    crc.update(data);
    return (int) crc.getValue();
  }

  static int crc16(byte[] data) {
    int crc = 0xffff;
    for (byte b : data) {
      crc = ((crc >>> 8) | (crc << 8)) & 0xffff;
      crc ^= u(b);
      crc ^= (crc & 255) >> 4;
      crc ^= (crc << 12) & 0xffff;
      crc ^= ((crc & 255) << 5) & 0xffff;
    }
    return crc & 0xffff;
  }

  @android.annotation.SuppressLint(
      "GetInstance") // Required by the existing watch wire protocol, not a new storage encryption
  // design.
  static byte[] aes(byte[] data, byte[] key, boolean encrypt) throws IOException {
    try {
      Cipher c = Cipher.getInstance("AES/ECB/NoPadding");
      c.init(encrypt ? Cipher.ENCRYPT_MODE : Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"));
      return c.doFinal(data);
    } catch (Exception e) {
      throw new IOException("Cifratura non riuscita");
    }
  }

  static byte[] readExactly(InputStream in, int size) throws IOException {
    byte[] result = new byte[size];
    int n = 0;
    while (n < size) {
      int got = in.read(result, n, size - n);
      if (got < 0) throw new EOFException("Connessione interrotta");
      if (got > 0) n += got;
    }
    return result;
  }

  static final class Packet {
    final int command, sequence;
    final byte[] payload;

    Packet(int command, int sequence, byte[] payload) {
      this.command = command;
      this.sequence = sequence;
      this.payload = payload;
    }
  }

  static byte[] frame(int command, int sequence, byte[] payload) throws IOException {
    require(payload.length <= 65535, "Frame troppo grande");
    byte[] body =
        buffer(payload.length + 4)
            .put((byte) command)
            .put((byte) sequence)
            .putShort((short) payload.length)
            .put(payload)
            .array();
    return buffer(payload.length + 8)
        .put((byte) 0x55)
        .put(body)
        .putShort((short) crc16(body))
        .put((byte) 0xaa)
        .array();
  }

  static Packet read(InputStream in) throws IOException {
    int start = in.read();
    if (start < 0) throw new EOFException("Connessione interrotta");
    require(start == 0x55, "Frame Bluetooth non riconosciuto");
    byte[] header = readExactly(in, 4);
    ByteBuffer h = le(header);
    int cmd = u(h.get()), seq = u(h.get()), len = h.getShort() & 65535;
    byte[] rest = readExactly(in, len + 3);
    ByteBuffer r = le(rest);
    byte[] payload = bytes(r, len);
    int checksum = r.getShort() & 65535;
    require(u(r.get()) == 0xaa, "Frame Bluetooth incompleto");
    require(
        crc16(buffer(header.length + len).put(header).put(payload).array()) == checksum,
        "Controllo integrita' Bluetooth fallito");
    return new Packet(cmd, seq, payload);
  }
}
