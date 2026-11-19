package com.example.syncbeat.zepp;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;

/** Transaction over only Zepp's Nearby devices permissions, with a durable undo record. */
public final class ZeppPermissionLease {
  public static final String[] PERMISSIONS = {
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.BLUETOOTH_ADVERTISE"
  };

  public interface Permissions {
    boolean granted(String name) throws IOException;
    void setGranted(String name, boolean value) throws IOException;
  }

  public interface Journal {
    Map<String, Boolean> read() throws IOException;
    void save(Map<String, Boolean> snapshot) throws IOException;
    void clear() throws IOException;
  }

  private final Permissions permissions;
  private final Journal journal;
  private boolean active;

  public ZeppPermissionLease(Permissions permissions, Journal journal) {
    this.permissions = permissions;
    this.journal = journal;
  }

  public synchronized void begin() throws IOException {
    if (active) throw new IOException("Un trasferimento coordinato è già in corso.");
    restore(); // Recover an interrupted transaction before taking another snapshot.
    Map<String, Boolean> snapshot = new LinkedHashMap<>();
    for (String name : PERMISSIONS) snapshot.put(name, permissions.granted(name));
    journal.save(snapshot); // Must be durable before the first permission change.
    active = true;
    try {
      for (String name : PERMISSIONS) {
        if (snapshot.get(name)) permissions.setGranted(name, false);
        if (permissions.granted(name)) throw new IOException("Impossibile sospendere Dispositivi nelle vicinanze per Zepp.");
      }
    } catch (IOException failure) {
      try { restore(); } catch (IOException restoreFailure) { failure.addSuppressed(restoreFailure); }
      throw failure;
    }
  }

  public synchronized void restore() throws IOException {
    active = false;
    Map<String, Boolean> snapshot = journal.read();
    if (snapshot == null) return;
    IOException failure = null;
    // Try all entries even if one fails; retain the undo record until all match.
    for (String name : PERMISSIONS) {
      Boolean original = snapshot.get(name);
      if (original == null) throw new IOException("Registro ripristino Zepp incompleto.");
      try {
        if (permissions.granted(name) != original) permissions.setGranted(name, original);
        if (permissions.granted(name) != original) throw new IOException("Ripristino del permesso Zepp non confermato.");
      } catch (IOException error) { failure = error; }
    }
    if (failure != null) throw failure;
    journal.clear();
  }

  public synchronized boolean pending() throws IOException { return journal.read() != null; }
}
