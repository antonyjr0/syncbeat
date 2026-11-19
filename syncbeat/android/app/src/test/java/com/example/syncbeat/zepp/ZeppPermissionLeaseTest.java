package com.example.syncbeat.zepp;

import static org.junit.Assert.*;
import java.io.IOException;
import java.util.*;
import org.junit.Test;

public class ZeppPermissionLeaseTest {
  @Test public void restoreQueuedDuringSlowBeginLeavesPermissionsGranted() throws Exception {
    java.util.concurrent.CountDownLatch revokeEntered = new java.util.concurrent.CountDownLatch(1);
    java.util.concurrent.CountDownLatch finishBegin = new java.util.concurrent.CountDownLatch(1);
    Access access = new Access() {
      @Override public void setGranted(String name, boolean value) throws IOException {
        if (!value && name.equals(ZeppPermissionLease.PERMISSIONS[0])) {
          revokeEntered.countDown();
          try {
            if (!finishBegin.await(5, java.util.concurrent.TimeUnit.SECONDS)) throw new IOException("Test did not release BEGIN");
          } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new IOException(error);
          }
        }
        super.setGranted(name, value);
      }
    };
    ZeppPermissionLease lease = new ZeppPermissionLease(access, new Journal());
    java.util.concurrent.ExecutorService server = java.util.concurrent.Executors.newSingleThreadExecutor();
    try {
      java.util.concurrent.Future<?> begin = server.submit(() -> { lease.begin(); return null; });
      assertTrue(revokeEntered.await(5, java.util.concurrent.TimeUnit.SECONDS));
      try { begin.get(1, java.util.concurrent.TimeUnit.MILLISECONDS); fail("BEGIN should still be blocked"); }
      catch (java.util.concurrent.TimeoutException expected) { }
      java.util.concurrent.Future<?> restore = server.submit(() -> { lease.restore(); return null; });
      assertFalse(restore.isDone());
      finishBegin.countDown();
      begin.get(5, java.util.concurrent.TimeUnit.SECONDS);
      restore.get(5, java.util.concurrent.TimeUnit.SECONDS);
      assertFalse(access.values.containsValue(false));
      assertFalse(lease.pending());
    } finally {
      finishBegin.countDown();
      server.shutdownNow();
    }
  }
  static class Access implements ZeppPermissionLease.Permissions {
    Map<String, Boolean> values = new LinkedHashMap<>();
    String failRevoke, failGrant;
    int changes;
    Access() { for (String name : ZeppPermissionLease.PERMISSIONS) values.put(name, true); }
    public boolean granted(String name) { return values.get(name); }
    public void setGranted(String name, boolean value) throws IOException {
      if (name.equals(value ? failGrant : failRevoke)) throw new IOException("Permission change rejected");
      changes++; values.put(name, value);
    }
  }
  static class Journal implements ZeppPermissionLease.Journal {
    Map<String, Boolean> saved;
    boolean failSave;
    public Map<String, Boolean> read() { return saved; }
    public void save(Map<String, Boolean> snapshot) throws IOException {
      if (failSave) throw new IOException("Disk unavailable");
      saved = new LinkedHashMap<>(snapshot);
    }
    public void clear() { saved = null; }
  }
  @Test public void restoresEntireGroupAfterSuccessOrTransferError() throws Exception {
    for (boolean transferFails : new boolean[] {false, true}) {
      Access access = new Access(); Journal journal = new Journal();
      ZeppPermissionLease lease = new ZeppPermissionLease(access, journal);
      try {
        lease.begin();
        assertFalse(access.values.containsValue(true));
        if (transferFails) throw new IOException("File rejected");
      } catch (IOException expected) {
        assertEquals("File rejected", expected.getMessage());
      } finally { lease.restore(); }
      assertFalse(access.values.containsValue(false));
      assertFalse(lease.pending());
    }
  }
  @Test public void doesNotGrantInitiallyDeniedPermissions() throws Exception {
    Access access = new Access(); Journal journal = new Journal();
    access.values.put(ZeppPermissionLease.PERMISSIONS[1], false);
    Map<String, Boolean> initial = new LinkedHashMap<>(access.values);
    ZeppPermissionLease lease = new ZeppPermissionLease(access, journal);
    lease.begin(); lease.restore();
    assertEquals(initial, access.values);
  }
  @Test public void durableRecordRecoversAfterClientOrHelperRestart() throws Exception {
    Access access = new Access(); Journal journal = new Journal();
    new ZeppPermissionLease(access, journal).begin();
    assertNotNull(journal.saved);
    new ZeppPermissionLease(access, journal).restore();
    assertFalse(access.values.containsValue(false));
    assertNull(journal.saved);
  }
  @Test public void failedRestoreStaysPendingAndCanBeRetried() throws Exception {
    Access access = new Access(); Journal journal = new Journal();
    ZeppPermissionLease lease = new ZeppPermissionLease(access, journal);
    lease.begin(); access.failGrant = ZeppPermissionLease.PERMISSIONS[0];
    try { lease.restore(); fail(); } catch (IOException expected) { }
    assertTrue(lease.pending());
    assertTrue(access.granted(ZeppPermissionLease.PERMISSIONS[1]));
    access.failGrant = null;
    lease.restore(); assertFalse(lease.pending());
    assertFalse(access.values.containsValue(false));
  }
  @Test public void partialRevokeFailureRollsBackBeforeReturning() throws Exception {
    Access access = new Access(); Journal journal = new Journal();
    access.failRevoke = ZeppPermissionLease.PERMISSIONS[1];
    ZeppPermissionLease lease = new ZeppPermissionLease(access, journal);
    try { lease.begin(); fail(); } catch (IOException expected) { }
    assertFalse(access.values.containsValue(false));
    assertFalse(lease.pending());
  }
  @Test public void cannotChangePermissionsWithoutSavingUndoRecord() throws Exception {
    Access access = new Access(); Journal journal = new Journal(); journal.failSave = true;
    try { new ZeppPermissionLease(access, journal).begin(); fail(); } catch (IOException expected) { }
    assertEquals(0, access.changes);
  }
  @Test public void restoreIsIdempotentForFinallyDeathAndWatchdog() throws Exception {
    Access access = new Access(); ZeppPermissionLease lease = new ZeppPermissionLease(access, new Journal());
    lease.begin(); lease.restore(); int changes = access.changes;
    lease.restore(); lease.restore();
    assertEquals(changes, access.changes);
  }
  @Test public void secondOperationCannotOverwriteOriginalSnapshot() throws Exception {
    Access access = new Access(); Journal journal = new Journal();
    ZeppPermissionLease lease = new ZeppPermissionLease(access, journal);
    lease.begin(); Map<String, Boolean> original = new LinkedHashMap<>(journal.saved);
    try { lease.begin(); fail(); } catch (IOException expected) { }
    assertEquals(original, journal.saved);
    lease.restore(); assertFalse(access.values.containsValue(false));
  }
}
