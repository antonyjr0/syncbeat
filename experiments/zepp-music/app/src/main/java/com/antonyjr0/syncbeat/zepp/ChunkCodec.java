/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Adapted 2026-11-16 from Gadgetbridge Huami2021ChunkedEncoder/Decoder
 * Copyright (C) 2022-2024 José Rebelo. Bounds/CRC checks and no payload logging added. */
package com.antonyjr0.syncbeat.zepp;

import java.io.*;
import java.nio.*;
import java.util.*;

final class ChunkCodec implements AutoCloseable {
  interface Sender {
    void send(byte[] bytes) throws IOException;
  }

  static final class Message {
    final int endpoint;
    final byte[] payload;

    Message(int endpoint, byte[] payload) {
      this.endpoint = endpoint;
      this.payload = payload;
    }
  }

  byte[] key;
  int sequence, writeHandle, mtu = 247;
  private int handle = -1, count, endpoint, plainLength;
  private boolean encrypted;
  private ByteBuffer received;
  int ackHandle, ackCount;
  boolean needsAck;

  void send(int type, byte[] data, boolean encrypt, Sender sender) throws IOException {
    Wire.require(data.length > 0 && data.length <= 65536, "Messaggio non valido");
    Wire.require(!encrypt || key != null, "Autenticazione necessaria");
    writeHandle = (writeHandle + 1) & 255;
    byte[] outgoing = data;
    if (encrypt) {
      byte[] k = messageKey(writeHandle);
      int length = (data.length + 8 + 15) / 16 * 16;
      ByteBuffer b = Wire.buffer(length).put(data).putInt(sequence++);
      b.putInt(Wire.crc32(Arrays.copyOf(b.array(), data.length + 4)));
      try {
        outgoing = Wire.aes(b.array(), k, true);
      } finally {
        Arrays.fill(k, (byte) 0);
      }
    }
    int position = 0, index = 0;
    while (position < outgoing.length) {
      int header = position == 0 ? 11 : 5,
          length = Math.min(outgoing.length - position, mtu - 3 - header);
      Wire.require(length > 0 && index <= 255, "MTU insufficiente");
      boolean last = position + length == outgoing.length;
      ByteBuffer b = Wire.buffer(header + length);
      b.put((byte) 3)
          .put((byte) ((encrypt ? 8 : 0) | (position == 0 ? 1 : 0) | (last ? 6 : 0)))
          .put((byte) 0)
          .put((byte) writeHandle)
          .put((byte) index++);
      if (position == 0) b.putInt(data.length).putShort((short) type);
      b.put(outgoing, position, length);
      sender.send(b.array());
      position += length;
    }
    if (encrypt) Arrays.fill(outgoing, (byte) 0);
  }

  Message accept(byte[] data) throws IOException {
    Wire.require(data.length >= 5, "Blocco protocollo incompleto");
    ByteBuffer b = Wire.le(data);
    Wire.require(Wire.u(b.get()) == 3, "Blocco protocollo sconosciuto");
    int flags = Wire.u(b.get());
    b.get();
    int h = Wire.u(b.get()), c = Wire.u(b.get());
    needsAck = (flags & 4) != 0;
    ackHandle = h;
    ackCount = c;
    if ((flags & 1) != 0) {
      Wire.require(handle < 0 && c == 0 && b.remaining() >= 6, "Inizio messaggio inatteso");
      plainLength = b.getInt();
      endpoint = b.getShort() & 65535;
      encrypted = (flags & 8) != 0;
      Wire.require(plainLength > 0 && plainLength <= 65536, "Lunghezza messaggio non valida");
      int length = encrypted ? (plainLength + 8 + 15) / 16 * 16 : plainLength;
      received = Wire.buffer(length);
      handle = h;
      count = 0;
    }
    Wire.require(
        received != null && handle == h && c == (count & 255), "Sequenza protocollo non valida");
    Wire.require(
        ((flags & 8) != 0) == encrypted && b.remaining() <= received.remaining(),
        "Blocco oltre i limiti");
    received.put(b);
    count++;
    if ((flags & 2) == 0) return null;
    Wire.require(!received.hasRemaining(), "Messaggio troncato");
    byte[] out = received.array();
    if (encrypted) {
      Wire.require(key != null, "Risposta cifrata prima dell'autenticazione");
      byte[] k = messageKey(handle);
      try {
        out = Wire.aes(out, k, false);
      } finally {
        Arrays.fill(k, (byte) 0);
      }
      int expected = Wire.le(out).getInt(plainLength + 4);
      Wire.require(
          Wire.crc32(Arrays.copyOf(out, plainLength + 4)) == expected,
          "Controllo integrita' messaggio fallito");
    }
    byte[] result = Arrays.copyOf(out, plainLength);
    int type = endpoint;
    Arrays.fill(out, (byte) 0);
    received = null;
    handle = -1;
    return new Message(type, result);
  }

  private byte[] messageKey(int h) {
    byte[] k = key.clone();
    for (int i = 0; i < k.length; i++) k[i] ^= (byte) h;
    return k;
  }

  public void close() {
    if (key != null) Arrays.fill(key, (byte) 0);
    key = null;
    if (received != null) Arrays.fill(received.array(), (byte) 0);
    received = null;
    handle = -1;
  }
}
