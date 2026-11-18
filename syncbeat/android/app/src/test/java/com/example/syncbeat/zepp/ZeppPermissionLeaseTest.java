package com.example.syncbeat.zepp;

import static org.junit.Assert.*;
import java.io.IOException;
import java.util.*;
import org.junit.Test;

public class ZeppPermissionLeaseTest {
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
