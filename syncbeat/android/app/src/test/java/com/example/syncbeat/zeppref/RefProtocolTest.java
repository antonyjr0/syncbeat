/* SPDX-License-Identifier: AGPL-3.0-or-later. Test fixtures contain generated test keys only. */
package com.example.syncbeat.zeppref;

import static org.junit.Assert.*;

import java.io.*;
import java.nio.*;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.*;
import org.junit.Test;

/**
 * Test JVM del flusso di riferimento: framing, codec endpoint, payload esatti e
 * un giro completo verifica+upload contro un orologio simulato che parla lo
 * stesso protocollo (loopback ECDH reale). Nessun hardware coinvolto.
 */
public class RefProtocolTest {
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
  public void crc32KnownVector() {
    assertEquals(0xCBF43926, RefWire.crc32("123456789".getBytes()));
  }

  @Test
  public void frameRoundTripAndChecksum() throws Exception {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    RefWire.writeFrame(out, 7, 255, new byte[] {1, 2, 3});
    byte[] raw = out.toByteArray();
    assertEquals(0x55, raw[0] & 0xff);
    assertEquals(0xaa, raw[raw.length - 1] & 0xff);
    InputStream drip =
        new ByteArrayInputStream(raw) {
          public synchronized int read(byte[] b, int off, int len) {
            return super.read(b, off, Math.min(len, 1));
          }
        };
    RefWire.Packet p = RefWire.readFrame(drip);
    assertEquals(7, p.command);
    assertEquals(255, p.sequence);
    assertArrayEquals(new byte[] {1, 2, 3}, p.payload);
    raw[6] ^= 1;
    fails(() -> RefWire.readFrame(new ByteArrayInputStream(raw)), "CRC");
  }

  @Test
  public void chunkedRoundTripMultiPart() throws Exception {
    byte[] data = new byte[300];
    new SecureRandom().nextBytes(data);
    RefChunked enc = new RefChunked();
    enc.maxPacket = 47; // forza multi-parte: payload primo 36, poi 42
    List<byte[]> packets = new ArrayList<>();
    enc.send(13, data, false, packets::add);
    assertTrue(packets.size() > 7);
    for (byte[] p : packets) assertTrue(p.length <= 47);
    assertEquals(0x03, packets.get(0)[0] & 0xff);
    assertEquals(1, packets.get(0)[1] & 0x01); // first
    ByteBuffer first = ByteBuffer.wrap(packets.get(0)).order(ByteOrder.LITTLE_ENDIAN);
    first.position(5);
    assertEquals(300, first.getInt());
    assertEquals(13, first.getShort() & 0xffff);
    int last = packets.size() - 1;
    assertEquals(0x06, packets.get(last)[1] & 0x06); // last + needsAck

    RefChunked dec = new RefChunked();
    RefChunked.Message message = null;
    for (byte[] p : packets) {
      RefChunked.Message m = dec.accept(p);
      if (m != null) message = m;
    }
    assertNotNull(message);
    assertEquals(13, message.endpoint);
    assertArrayEquals(data, message.payload);
    assertTrue(dec.ackPending);
  }

  @Test
  public void chunkedEncryptedRoundTrip() throws Exception {
    byte[] key = new byte[16];
    new SecureRandom().nextBytes(key);
    byte[] data = new byte[100];
    new SecureRandom().nextBytes(data);
    RefChunked enc = new RefChunked();
    enc.key = key.clone();
    enc.sequence = 42;
    List<byte[]> packets = new ArrayList<>();
    enc.send(130, data, true, packets::add);
    for (byte[] p : packets) assertEquals(0x08, p[1] & 0x08);

    RefChunked dec = new RefChunked();
    dec.key = key.clone();
    RefChunked.Message message = null;
    for (byte[] p : packets) {
      RefChunked.Message m = dec.accept(p);
      if (m != null) message = m;
    }
    assertNotNull(message);
    assertArrayEquals(data, message.payload);

    // Manomissione: il CRC del messaggio cifrato deve fallire.
    RefChunked dec2 = new RefChunked();
    dec2.key = key.clone();
    List<byte[]> tampered = new ArrayList<>();
    for (byte[] p : packets) tampered.add(p.clone());
    byte[] lastPacket = tampered.get(tampered.size() - 1);
    lastPacket[lastPacket.length - 1] ^= 1;
    fails(
        () -> {
          for (byte[] p : tampered) dec2.accept(p);
        },
        "CRC");
  }

  @Test
  public void uploadRequestExactBytes() throws Exception {
    // Stessa costruzione di RefFlow.upload: layout atteso dai riferimenti
    // (OronBox _requestPayload, GB ZeppOsFileTransferV3.uploadFile).
    byte[] mp3 = new byte[1000];
    new SecureRandom().nextBytes(mp3);
    byte[] url = RefWire.utf8z("music://file?songName=Test&singer=Artist&end=1");
    byte[] name = RefWire.utf8z("syncbeat-test.mp3");
    ByteBuffer request =
        RefWire.le(2 + url.length + name.length + 10)
            .put((byte) 3)
            .put((byte) 0)
            .put(url)
            .put(name)
            .putInt(mp3.length)
            .putInt(RefWire.crc32(mp3))
            .put((byte) 0)
            .put((byte) 0);
    byte[] got = request.array();

    ByteArrayOutputStream expected = new ByteArrayOutputStream();
    expected.write(3);
    expected.write(0);
    expected.write("music://file?songName=Test&singer=Artist&end=1".getBytes("UTF-8"));
    expected.write(0);
    expected.write("syncbeat-test.mp3".getBytes("UTF-8"));
    expected.write(0);
    ByteBuffer tail = ByteBuffer.allocate(10).order(ByteOrder.LITTLE_ENDIAN);
    tail.putInt(1000).putInt(RefWire.crc32(mp3)).put((byte) 0).put((byte) 0);
    expected.write(tail.array());
    assertArrayEquals(expected.toByteArray(), got);
  }

  // ---- orologio simulato: giro completo initialize + upload ----

  private static final String W = RefFlow.CHUNKED_WRITE;
  private static final String R = RefFlow.CHUNKED_READ;
  private static final String F = RefFlow.FILE_SEND;

  private static final class FakeWatch implements Runnable {
    final InputStream in;
    final OutputStream out;
    final byte[] authKey;
    final byte[] expectedMp3;
    volatile Throwable failure;
    int mtu = 247;
    int chunkSize = 512;
    int session = 7;

    FakeWatch(InputStream in, OutputStream out, byte[] authKey, byte[] expectedMp3) {
      this.in = in;
      this.out = out;
      this.authKey = authKey;
      this.expectedMp3 = expectedMp3;
    }

    Map<Integer, String> channelNames() {
      Map<Integer, String> byChannel = new HashMap<>();
      byChannel.put(4, W);
      byChannel.put(5, R);
      byChannel.put(6, F);
      return byChannel;
    }

    int channelOf(String uuid) {
      for (Map.Entry<Integer, String> e : channelNames().entrySet())
        if (e.getValue().equals(uuid)) return e.getKey();
      return -1;
    }

    void sendEndpoint(OutputStream channelOut, RefChunked codec, int endpoint, byte[] data, boolean encrypt)
        throws IOException {
      codec.send(
          endpoint,
          data,
          encrypt,
          packet -> writeChannelFrame(channelOut, channelOf(R), packet));
    }

    synchronized void writeChannelFrame(OutputStream out, int channel, byte[] data) throws IOException {
      ByteBuffer b = RefWire.le(data.length + 4).put((byte) session).putShort((short) channel).put((byte) 0);
      b.put(data);
      RefWire.writeFrame(out, 7, 0, b.array());
    }

    public void run() {
      try {
        RefChunked codec = new RefChunked();
        codec.maxPacket = mtu;
        // Fase 1: tabella canali
        RefWire.Packet p = RefWire.readFrame(in);
        assertEquals(1, p.command);
        ByteArrayOutputStream table = new ByteArrayOutputStream();
        table.write(1);
        int count = 3;
        table.write(count & 0xff);
        table.write(0);
        for (Map.Entry<Integer, String> e : channelNames().entrySet()) {
          table.write(e.getValue().getBytes("UTF-8"));
          table.write(0);
          table.write(e.getKey() & 0xff);
          table.write((e.getKey() >> 8) & 0xff);
        }
        RefWire.writeFrame(out, 2, 0, table.toByteArray());
        // Fase 2: avvio sessione
        p = RefWire.readFrame(in);
        assertEquals(3, p.command);
        int nonce = ByteBuffer.wrap(p.payload).order(ByteOrder.LITTLE_ENDIAN).getInt();
        RefWire.writeFrame(
            out,
            4,
            1,
            RefWire.le(8)
                .putInt(nonce)
                .put((byte) 1)
                .put((byte) session)
                .putShort((short) mtu)
                .array());
        // Fase 3: autenticazione ECDH reale
        byte[] priv = new byte[24];
        new SecureRandom().nextBytes(priv);
        byte[] watchPub = com.example.syncbeat.zepp.ECDH_B163.ecdh_generate_public(priv);
        byte[] random16 = new byte[16];
        new SecureRandom().nextBytes(random16);
        byte[] authReq = nextMessage(codec, channelOf(W), 130);
        assertEquals(4, authReq[0]);
        assertEquals(52, authReq.length);
        byte[] phonePub = Arrays.copyOfRange(authReq, 4, 52);
        byte[] shared = com.example.syncbeat.zepp.ECDH_B163.ecdh_generate_shared(priv, phonePub);
        byte[] sessionKey = new byte[16];
        for (int i = 0; i < 16; i++) sessionKey[i] = (byte) (shared[i + 8] ^ authKey[i]);
        codec.sequence = ByteBuffer.wrap(shared, 0, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
        codec.key = sessionKey;
        ByteBuffer authResp = RefWire.le(67).put(new byte[] {0x10, 4, 1}).put(random16);
        authResp.put(watchPub);
        RefChunked authCodec = new RefChunked();
        authCodec.maxPacket = mtu;
        sendEndpoint(out, authCodec, 130, authResp.array(), false);
        byte[] proof = nextMessage(codec, channelOf(W), 130);
        assertEquals(5, proof[0]);
        assertEquals(33, proof.length);
        assertArrayEquals(
            random16, RefWire.aesEcb(Arrays.copyOfRange(proof, 1, 17), authKey, false));
        assertArrayEquals(
            random16, RefWire.aesEcb(Arrays.copyOfRange(proof, 17, 33), sessionKey, false));
        RefChunked clearCodec = new RefChunked();
        clearCodec.maxPacket = mtu;
        sendEndpoint(out, clearCodec, 130, new byte[] {0x10, 5, 1}, false);
        // Fase 4: servizi (endpoint 13 cifrato = 1, per esercitare quel percorso)
        byte[] svcReq = nextMessage(codec, channelOf(W), 0);
        assertArrayEquals(new byte[] {3}, svcReq);
        RefChunked svcCodec = new RefChunked();
        svcCodec.maxPacket = mtu;
        sendEndpoint(out, svcCodec, 0, new byte[] {4, 1, 0, 13, 0, 1}, false);
        // Fase 5: capacita' (cifrata)
        byte[] capsReq = nextMessage(codec, channelOf(W), 13);
        assertArrayEquals(new byte[] {1}, capsReq);
        ByteArrayOutputStream caps = new ByteArrayOutputStream();
        caps.write(2);
        caps.write(3);
        caps.write(chunkSize & 0xff);
        caps.write((chunkSize >> 8) & 0xff);
        caps.write(new byte[] {0, 0, 0, 0}, 0, 4);
        caps.write(1);
        caps.write(0);
        caps.write("music".getBytes("UTF-8"));
        caps.write(0);
        sendEndpoint(out, codec, 13, caps.toByteArray(), true);
        // Fase 6: richiesta upload (cifrata)
        byte[] uploadReq = nextMessage(codec, channelOf(W), 13);
        assertEquals(3, uploadReq[0]);
        assertEquals(0, uploadReq[1]);
        ByteBuffer req = ByteBuffer.wrap(uploadReq).order(ByteOrder.LITTLE_ENDIAN);
        req.position(2);
        String url = cstring(req);
        String name = cstring(req);
        assertEquals("music://file?songName=Test&singer=Artist&end=1", url);
        assertEquals("syncbeat-test.mp3", name);
        assertEquals(expectedMp3.length, req.getInt());
        assertEquals(RefWire.crc32(expectedMp3), req.getInt());
        sendEndpoint(out, codec, 13, new byte[] {4, 0, 0, 0, 0, 0, 0}, true);
        // Fase 7: chunk dati sul canale FILE_SEND
        ByteArrayOutputStream received = new ByteArrayOutputStream();
        int index = 0;
        while (received.size() < expectedMp3.length) {
          // riassembla un chunk intero: header 5 + n
          byte[] header = readChannelBytes(5);
          assertEquals(0x12, header[0] & 0xff);
          int n =
              (header[3] & 0xff) | ((header[4] & 0xff) << 8);
          byte[] body = readChannelBytes(n);
          received.write(body);
          assertEquals(index & 0xff, header[2] & 0xff);
          writeChannelFrame(out, channelOf(F), new byte[] {0x13, 0, (byte) index});
          index++;
        }
        assertArrayEquals(expectedMp3, received.toByteArray());
      } catch (Throwable t) {
        failure = t;
      }
    }

    static String cstring(ByteBuffer b) {
      StringBuilder s = new StringBuilder();
      while (b.hasRemaining()) {
        byte v = b.get();
        if (v == 0) return s.toString();
        s.append((char) (v & 0xff));
      }
      return s.toString();
    }

    /** Legge dati grezzi sul canale FILE_SEND fino a n byte complessivi. */
    byte[] fileSendBuffer = new byte[0];

    byte[] readChannelBytes(int n) throws IOException {
      int fileChannel = channelOf(F);
      while (fileSendBuffer.length < n) {
        RefWire.Packet p = RefWire.readFrame(in);
        assertEquals(7, p.command);
        ByteBuffer b = ByteBuffer.wrap(p.payload).order(ByteOrder.LITTLE_ENDIAN);
        b.get();
        int channel = b.getShort() & 0xffff;
        b.get();
        if (channel != fileChannel) continue; // ack del codec sul canale READ, ecc.
        byte[] data = new byte[b.remaining()];
        b.get(data);
        ByteArrayOutputStream joined = new ByteArrayOutputStream();
        joined.write(fileSendBuffer);
        joined.write(data);
        fileSendBuffer = joined.toByteArray();
      }
      byte[] result = Arrays.copyOfRange(fileSendBuffer, 0, n);
      fileSendBuffer = Arrays.copyOfRange(fileSendBuffer, n, fileSendBuffer.length);
      return result;
    }

    byte[] nextMessage(RefChunked codec, int writeChannel, int endpoint) throws IOException {
      while (true) {
        RefChunked.Message m = codec.accept(readChannelData(writeChannel));
        if (m != null) {
          assertEquals(endpoint, m.endpoint);
          return m.payload;
        }
      }
    }

    byte[] readChannelData(int writeChannel) throws IOException {
      while (true) {
        RefWire.Packet p = RefWire.readFrame(in);
        assertEquals(7, p.command);
        ByteBuffer b = ByteBuffer.wrap(p.payload).order(ByteOrder.LITTLE_ENDIAN);
        b.get();
        int channel = b.getShort() & 0xffff;
        b.get();
        if (channel != writeChannel) continue;
        byte[] data = new byte[b.remaining()];
        b.get(data);
        return data;
      }
    }
  }

  @Test
  public void fullVerifyAndUploadAgainstFakeWatch() throws Exception {
    byte[] authKey = new byte[16];
    new SecureRandom().nextBytes(authKey);
    byte[] mp3 = new byte[1000];
    new SecureRandom().nextBytes(mp3);

    PipedOutputStream phoneOut = new PipedOutputStream();
    PipedInputStream watchIn = new PipedInputStream(phoneOut, 1 << 16);
    PipedOutputStream watchOut = new PipedOutputStream();
    PipedInputStream phoneIn = new PipedInputStream(watchOut, 1 << 16);

    FakeWatch watch = new FakeWatch(watchIn, watchOut, authKey, mp3);
    Thread watchThread = new Thread(watch, "fake-watch");
    watchThread.setDaemon(true);
    watchThread.start();

    List<String> phases = new CopyOnWriteArrayList<>();
    int[] lastProgress = {0, 0};
    RefFlow flow =
        new RefFlow(
            phoneIn,
            phoneOut,
            new RefFlow.Events() {
              public void phase(String text) {
                phases.add(text);
              }

              public void progress(int done, int total) {
                lastProgress[0] = done;
                lastProgress[1] = total;
              }
            });
    try {
      flow.initialize(authKey);
      flow.upload(mp3, "Test", "Artist");
      flow.close();
    } catch (Throwable phoneError) {
      watchThread.join(10000);
      if (watch.failure != null) fail("fake watch: " + watch.failure + " (lato telefono: " + phoneError + ")");
      throw phoneError;
    }
    watchThread.join(10000);

    if (watch.failure != null) {
      fail("fake watch: " + watch.failure);
    }
    assertEquals(1000, lastProgress[0]);
    assertEquals(1000, lastProgress[1]);
    assertTrue(phases.stream().anyMatch(s -> s.contains("mtu=247")));
    assertTrue(phases.stream().anyMatch(s -> s.contains("chunkSize=512")));
    assertTrue(phases.stream().anyMatch(s -> s.startsWith("8/8")));
  }
}
