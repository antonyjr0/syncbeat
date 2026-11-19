/* SPDX-License-Identifier: AGPL-3.0-or-later. Test fixtures contain generated test keys only. */
package com.example.syncbeat.zepp;

import static org.junit.Assert.*;

import java.io.*;
import java.nio.*;
import java.security.SecureRandom;
import java.util.*;
import org.junit.Test;

public class ProtocolTest {
  private interface Checked {
    void run() throws Exception;
  }

  private void fails(Checked run, String part) throws Exception {
    try {
      run.run();
      fail("Expected failure");
    } catch (IOException e) {
      assertTrue(e.getMessage(), e.getMessage().contains(part));
    }
  }

  @Test
  public void frameFragmentationAndChecksum() throws Exception {
    byte[] raw = Wire.frame(7, 255, new byte[] {1, 2, 3});
    InputStream fragmented =
        new ByteArrayInputStream(raw) {
          public synchronized int read(byte[] b, int off, int len) {
            return super.read(b, off, Math.min(len, 1));
          }
        };
    Wire.Packet p = Wire.read(fragmented);
    assertEquals(255, p.sequence);
    assertArrayEquals(new byte[] {1, 2, 3}, p.payload);
    raw[6] ^= 1;
    fails(() -> Wire.read(new ByteArrayInputStream(raw)), "integrita");
  }

  @Test
  public void shortFrameIsRejected() throws Exception {
    fails(() -> Wire.read(new ByteArrayInputStream(new byte[] {0x55, 1})), "interrotta");
  }

  @Test
  public void concatenatedFramesAreSeparate() throws Exception {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    out.write(Wire.frame(1, 1, new byte[0]));
    out.write(Wire.frame(2, 2, new byte[] {9}));
    InputStream in = new ByteArrayInputStream(out.toByteArray());
    assertEquals(1, Wire.read(in).command);
    assertEquals(2, Wire.read(in).command);
  }

  @Test
  public void keyValidationNeverEchoesInput() throws Exception {
    assertEquals(16, ZeppSession.parseKey("0123456789abcdef0123456789abcdef".toCharArray()).length);
    assertEquals(
        16, ZeppSession.parseKey("0x0123456789abcdef0123456789abcdef".toCharArray()).length);
    fails(() -> ZeppSession.parseKey("bad".toCharArray()), "32 cifre");
    fails(
        () -> ZeppSession.parseKey("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz".toCharArray()), "non valida");
  }

  @Test
  public void metadataSeparatorsFailClosed() throws Exception {
    ZeppSession.validateMetadata("Citta' di notte");
    fails(() -> ZeppSession.validateMetadata("titolo&singer=altro"), "evita");
    fails(() -> ZeppSession.validateMetadata("a\0b"), "evita");
    ZeppSession.validateMetadata("a".repeat(31));
    fails(() -> ZeppSession.validateMetadata("a".repeat(32)), "31 byte");
    ZeppSession.validateMetadata("è".repeat(15));
    fails(() -> ZeppSession.validateMetadata("è".repeat(16)), "31 byte");
  }

  @Test
  public void chunksRoundTripWithEncryption() throws Exception {
    ChunkCodec enc = new ChunkCodec(), dec = new ChunkCodec();
    enc.key = new byte[16];
    dec.key = new byte[16];
    enc.mtu = 64;
    byte[] data = new byte[1000];
    new SecureRandom().nextBytes(data);
    List<byte[]> chunks = new ArrayList<>();
    enc.send(13, data, true, chunks::add);
    ChunkCodec.Message m = null;
    for (byte[] c : chunks) {
      ChunkCodec.Message next = dec.accept(c);
      if (next != null) m = next;
    }
    assertNotNull(m);
    assertArrayEquals(data, m.payload);
    assertEquals(13, m.endpoint);
    assertTrue(dec.needsAck);
    enc.close();
    dec.close();
  }

  @Test
  public void chunkOrderingAndBoundsAreChecked() throws Exception {
    ChunkCodec enc = new ChunkCodec(), dec = new ChunkCodec();
    enc.mtu = 32;
    List<byte[]> chunks = new ArrayList<>();
    enc.send(1, new byte[100], false, chunks::add);
    dec.accept(chunks.get(0));
    chunks.get(1)[4] = 7;
    fails(() -> dec.accept(chunks.get(1)), "Sequenza");
    ChunkCodec d = new ChunkCodec();
    byte[] absurd =
        Wire.buffer(11)
            .put(new byte[] {3, 1, 0, 1, 0})
            .putInt(Integer.MAX_VALUE)
            .putShort((short) 1)
            .array();
    fails(() -> d.accept(absurd), "Lunghezza");
  }

  @Test
  public void encryptedChunkCorruptionIsRejected() throws Exception {
    ChunkCodec a = new ChunkCodec(), b = new ChunkCodec();
    a.key = new byte[16];
    b.key = new byte[16];
    List<byte[]> chunks = new ArrayList<>();
    a.send(0, new byte[] {1, 2, 3}, true, chunks::add);
    chunks.get(0)[11] ^= 1;
    fails(() -> b.accept(chunks.get(0)), "integrita");
  }

  @Test
  public void ecdhAgreementAndInvalidPoint() throws Exception {
    byte[] a = new byte[24], b = new byte[24];
    new SecureRandom().nextBytes(a);
    new SecureRandom().nextBytes(b);
    assertArrayEquals(
        ECDH_B163.ecdh_generate_shared(a, ECDH_B163.ecdh_generate_public(b)),
        ECDH_B163.ecdh_generate_shared(b, ECDH_B163.ecdh_generate_public(a)));
    assertNull(ECDH_B163.ecdh_generate_shared(a, new byte[48]));
  }

  @Test
  public void realClientCompletesAgainstScriptedWatchAndRollsIndex() throws Exception {
    Watch w = new Watch();
    ZeppSession c = w.client();
    c.initialize(w.key);
    byte[] mp3 = new byte[6000];
    c.upload(mp3, "Prova", "Artista");
    assertEquals(6000, w.accepted);
    assertTrue(w.finalAck);
    assertEquals(100, w.lastPercent);
    c.close();
  }

  @Test
  public void missingMusicNeverUploads() throws Exception {
    Watch w = new Watch();
    w.music = false;
    fails(() -> w.client().initialize(w.key), "non dichiara");
    assertEquals(0, w.accepted);
  }

  @Test
  public void rejectedAuthDoesNotRequestCapabilities() throws Exception {
    Watch w = new Watch();
    w.rejectAuth = true;
    fails(() -> w.client().initialize(w.key), "Autenticazione rifiutata");
    assertFalse(w.capabilitiesRequested);
  }

  @Test
  public void unsupportedTransferVersionIsRejected() throws Exception {
    Watch w = new Watch();
    w.version = 2;
    fails(() -> w.client().initialize(w.key), "solo file transfer V3");
  }

  @Test
  public void wrongAckStopsBeforeSuccess() throws Exception {
    Watch w = new Watch();
    w.badAck = true;
    ZeppSession c = w.client();
    c.initialize(w.key);
    fails(() -> c.upload(new byte[100], "Test", ""), "Conferma blocco errata");
    assertFalse(w.finalAck);
    assertEquals(0, w.lastPercent);
  }

  @Test
  public void missingFinalAckDoesNotReportHundredPercent() throws Exception {
    Watch w = new Watch();
    w.dropFinal = true;
    ZeppSession c = w.client();
    c.initialize(w.key);
    fails(() -> c.upload(new byte[32], "Test", ""), "interrotta");
    assertEquals(50, w.lastPercent);
  }

  @Test
  public void nonzeroResumeIsNotSilentlyAccepted() throws Exception {
    Watch w = new Watch();
    w.resume = 1;
    ZeppSession c = w.client();
    c.initialize(w.key);
    fails(() -> c.upload(new byte[100], "Test", ""), "ripresa non ancora verificata");
    assertEquals(0, w.accepted);
  }

  @Test
  public void uploadResponseDistinguishesRejectionSessionAndMalformedData() throws Exception {
    assertEquals(0, ZeppSession.parseUploadResponse(new byte[] {4, 0, 0, 0, 0, 0, 0}));
    fails(() -> ZeppSession.parseUploadResponse(new byte[] {4, 0, 7}), "codice 7");
    fails(() -> ZeppSession.parseUploadResponse(new byte[] {4, 1, 0}), "Sessione importazione");
    fails(() -> ZeppSession.parseUploadResponse(new byte[] {5, 0, 0}), "comando 5");
    fails(() -> ZeppSession.parseUploadResponse(new byte[] {4}), "intestazione");
    fails(() -> ZeppSession.parseUploadResponse(new byte[] {4, 0, 0}), "avanzamento");
  }

  @Test
  public void rejectedImportNeverSendsAudioBlocks() throws Exception {
    Watch w = new Watch();
    w.uploadStatus = 7;
    ZeppSession c = w.client();
    c.initialize(w.key);
    fails(() -> c.upload(new byte[100], "Test", ""), "codice 7");
    assertEquals(0, w.accepted);
    assertFalse(w.finalAck);
    c.close();
  }

  @Test
  public void uploadRequiresSuccessfulCapabilityCheck() throws Exception {
    Watch w = new Watch();
    fails(() -> w.client().upload(new byte[10], "Test", ""), "Verifica prima");
    assertEquals(0, w.accepted);
  }

  @Test
  public void unsignedChunkSize32768AndFragmentedUpload() throws Exception {
    Watch w = new Watch();
    w.negotiatedChunkSize = 32768;
    ZeppSession c = w.client();
    c.initialize(w.key);
    c.upload(new byte[65537], "Grande", "Artista");
    assertEquals(65537, w.accepted);
    assertTrue(w.finalAck);
    assertEquals(100, w.lastPercent);
  }

  @Test
  public void wrongSessionIsRejected() throws Exception {
    Watch w = new Watch();
    w.wrongSession = true;
    fails(() -> w.client().initialize(w.key), "Sessione Bluetooth cambiata");
  }

  @Test
  public void interleavedPingGetsReply() throws Exception {
    Watch w = new Watch();
    w.pingBeforeAuth = true;
    ZeppSession c = w.client();
    c.initialize(w.key);
    assertTrue(w.pongReceived);
    c.close();
  }

  @Test
  public void closedSessionCannotUpload() throws Exception {
    Watch w = new Watch();
    ZeppSession c = w.client();
    c.initialize(w.key);
    c.close();
    fails(() -> c.upload(new byte[20], "Test", ""), "Verifica prima");
  }

  // No Bluetooth and no claim of hardware compatibility. This peer speaks the same documented
  // source-derived protocol.
  static class Watch extends OutputStream {
    final byte[] key = new byte[16], privateKey = new byte[24], random = new byte[16];
    final ArrayDeque<Integer> queue = new ArrayDeque<>();
    final ChunkCodec codec = new ChunkCodec();
    int negotiatedChunkSize = 16;
    boolean wrongSession, pingBeforeAuth, pongReceived;
    boolean music = true, rejectAuth, badAck, dropFinal, finalAck, capabilitiesRequested;
    int sequence, version = 3, accepted, total, index, lastPercent, resume, uploadStatus;
    ByteArrayOutputStream file = new ByteArrayOutputStream();

    Watch() {
      new SecureRandom().nextBytes(privateKey);
      new SecureRandom().nextBytes(random);
    }

    ZeppSession client() {
      return new ZeppSession(
          new InputStream() {
            public int read() {
              return queue.isEmpty() ? -1 : queue.remove();
            }
          },
          this,
          new ZeppSession.Events() {
            public void status(String s) {}

            public void progress(int n, int t) {
              lastPercent = (int) (100L * n / t);
            }
          });
    }

    void reply(int cmd, byte[] data) throws IOException {
      for (byte b : Wire.frame(cmd, sequence++ & 255, data)) queue.add(b & 255);
    }

    void characteristic(int channel, byte[] data) throws IOException {
      reply(
          7,
          Wire.buffer(data.length + 4)
              .put((byte) (wrongSession ? 9 : 3))
              .putShort((short) channel)
              .put((byte) 0)
              .put(data)
              .array());
    }

    void service(int endpoint, byte[] data, boolean encrypted) throws IOException {
      codec.send(endpoint, data, encrypted, b -> characteristic(2, b));
    }

    @Override
    public void write(int b) {
      throw new UnsupportedOperationException();
    }

    @Override
    public void write(byte[] data) throws IOException {
      Wire.Packet p = Wire.read(new ByteArrayInputStream(data));
      ByteBuffer b = Wire.le(p.payload);
      if (p.command == 1) {
        String[] names = {
          ZeppSession.WRITE, ZeppSession.READ, ZeppSession.FILE_SEND, ZeppSession.FILE_RECEIVE
        };
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(new byte[] {1, 4, 0});
        for (int i = 0; i < 4; i++) {
          out.write(Wire.text(names[i]));
          out.write(new byte[] {(byte) (i + 1), 0});
        }
        reply(2, out.toByteArray());
        return;
      }
      if (p.command == 3) {
        reply(
            4,
            Wire.buffer(8)
                .putInt(b.getInt())
                .put((byte) 1)
                .put((byte) 3)
                .putShort((short) 247)
                .array());
        return;
      }
      if (p.command == 10) {
        pongReceived = true;
        return;
      }
      if (p.command != 7) return;
      b.get();
      int channel = b.getShort() & 65535;
      b.get();
      byte[] payload = Wire.bytes(b, b.remaining());
      if (channel == 1) {
        ChunkCodec.Message m = codec.accept(payload);
        if (m == null) return;
        if (m.endpoint == 130 && m.payload[0] == 4) {
          if (pingBeforeAuth) reply(9, new byte[] {3, 0, 0, 0});
          byte[] pub = ECDH_B163.ecdh_generate_public(privateKey);
          byte[] shared =
              ECDH_B163.ecdh_generate_shared(privateKey, Arrays.copyOfRange(m.payload, 4, 52));
          codec.key = new byte[16];
          for (int i = 0; i < 16; i++) codec.key[i] = (byte) (shared[i + 8] ^ key[i]);
          service(
              130,
              Wire.buffer(67).put(new byte[] {0x10, 4, 1}).put(random).put(pub).array(),
              false);
        } else if (m.endpoint == 130 && m.payload[0] == 5) {
          assertArrayEquals(Wire.aes(random, key, true), Arrays.copyOfRange(m.payload, 1, 17));
          assertArrayEquals(
              Wire.aes(random, codec.key, true), Arrays.copyOfRange(m.payload, 17, 33));
          service(130, new byte[] {0x10, 5, (byte) (rejectAuth ? 0x25 : 1)}, false);
        } else if (m.endpoint == 0) {
          service(0, new byte[] {4, 1, 0, 13, 0, 1}, false);
        } else if (m.endpoint == 13 && m.payload[0] == 1) {
          capabilitiesRequested = true;
          byte[] name = Wire.text(music ? "music" : "sport");
          service(
              13,
              Wire.buffer(10 + name.length)
                  .put((byte) 2)
                  .put((byte) version)
                  .putShort((short) negotiatedChunkSize)
                  .putInt(0)
                  .putShort((short) 1)
                  .put(name)
                  .array(),
              true);
        } else if (m.endpoint == 13 && m.payload[0] == 3) {
          ByteBuffer r = Wire.le(m.payload);
          r.get();
          r.get();
          assertTrue(Wire.string(r, 1024).startsWith("music://file?songName="));
          Wire.string(r, 128);
          total = r.getInt();
          service(13, Wire.buffer(7).put(new byte[] {4, 0, (byte) uploadStatus}).putInt(resume).array(), true);
        }
      } else if (channel == 3) {
        file.write(payload);
        byte[] raw = file.toByteArray();
        if (raw.length < 5) return;
        int len = Wire.le(raw).getShort(3) & 65535;
        if (raw.length < 5 + len) return;
        assertEquals(5 + len, raw.length);
        assertEquals(index & 255, raw[2] & 255);
        accepted += len;
        file.reset();
        if (accepted == total && dropFinal) return;
        characteristic(3, new byte[] {0x13, 0, (byte) (badAck ? index + 1 : index), 0});
        index++;
        if (accepted == total && !badAck) finalAck = true;
      }
    }
  }
}
