/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Antonio Guarini. Experimental Android host for the adapted Zepp client. */
package com.antonyjr0.syncbeat.zepp;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

@android.annotation.SuppressLint(
    "SetTextI18n") // Italian-only experimental UI; no translation resources yet.
public final class PrototypeActivity extends Activity {
  private LinearLayout column;
  private TextView status, fileLabel;
  private EditText keyField, title, artist;
  private Spinner devices;
  private Button connect, upload, choose, refresh;
  private ProgressBar progress;
  private final List<BluetoothDevice> bonded = new ArrayList<>();
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
  private volatile BluetoothSocket socket;
  private volatile InputStream selectedInput;
  private volatile ZeppSession client;
  private volatile int generation;
  private boolean busy, ready;
  private byte[] mp3;
  private ScheduledFuture<?> deadline;
  private static final int PICK = 4210, CONNECT_PERMISSION = 4211;

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    // Enabled before the secret can be typed; remains set until Activity destruction.
    ScrollView scroll = new ScrollView(this);
    scroll.setBackgroundColor(Color.WHITE);
    column = new LinearLayout(this);
    column.setOrientation(LinearLayout.VERTICAL);
    column.setFocusableInTouchMode(true);
    column.requestFocus();
    int pad = dp(20);
    column.setPadding(pad, pad, pad, pad);
    scroll.setFillViewport(true);
    scroll.addView(column);
    setContentView(scroll);
    scroll.setOnApplyWindowInsetsListener(
        (v, insets) -> {
          v.setPadding(
              insets.getSystemWindowInsetLeft(),
              insets.getSystemWindowInsetTop(),
              insets.getSystemWindowInsetRight(),
              insets.getSystemWindowInsetBottom());
          return insets;
        });
    heading("SyncBeat Zepp Lab", 26);
    text("PROTOTIPO SPERIMENTALE · Classic / V3", 13, Color.rgb(38, 100, 78));
    text(
        "Questa app separata prova il collegamento e l'importazione nel lettore Musica originale."
            + " Non e' ancora verificata sul tuo firmware. Nessun collegamento parte da solo.",
        16,
        Color.DKGRAY);
    text(
        "Prima sincronizza le attivita' in Zepp. Non resettare e non disassociare l'orologio. Leggi"
            + " la guida nel repository prima di iniziare.",
        16,
        Color.rgb(145, 68, 22));
    heading("1. Prepara un MP3", 20);
    choose = button("Scegli un MP3 locale", v -> chooseFile());
    fileLabel = text("Nessun file selezionato (massimo 32 MiB).", 14, Color.DKGRAY);
    title = field("Titolo del brano", false);
    artist = field("Artista", false);
    heading("2. Scegli il tuo orologio", 20);
    text(
        "Solo dispositivi gia' abbinati ad Android. Nessuna scansione e nessun nuovo abbinamento.",
        14,
        Color.DKGRAY);
    devices = new Spinner(this);
    column.addView(devices, new LinearLayout.LayoutParams(-1, dp(56)));
    refresh = button("Mostra dispositivi abbinati", v -> loadDevices());
    keyField = field("Chiave (32 cifre hex)", true);
    text(
        "Chiave solo in memoria per questa sessione. Non e' la password Zepp. Non inviarla in chat"
            + " o nei log. Se non la possiedi, fermati e chiedi assistenza sul percorso sicuro.",
        14,
        Color.DKGRAY);
    connect = button("Verifica collegamento e servizio music", v -> confirmConnection());
    heading("3. Invia un solo brano", 20);
    upload = button("Invia MP3 al lettore nativo", v -> confirmUpload());
    upload.setEnabled(false);
    button(
        "Interrompi e scollega",
        v -> {
          disconnect();
          show("Connessione chiusa. Per riprovare, verifica di nuovo il collegamento.");
        });
    progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
    progress.setMax(100);
    column.addView(progress, new LinearLayout.LayoutParams(-1, dp(24)));
    status =
        text(
            "In attesa. Seleziona il file prima di collegarti: lasciare questa schermata chiude la"
                + " connessione.",
            16,
            Color.DKGRAY);
    button(
        "Licenza e codice riutilizzato",
        v ->
            new AlertDialog.Builder(this)
                .setTitle("AGPL-3.0-or-later")
                .setMessage(
                    "Versione sperimentale derivata da Gadgetbridge. Copyright José Rebelo, Andreas"
                        + " Shimokawa e contributori; modifiche 16/11/2026. Senza garanzia."
                        + " Sorgenti, licenza integrale e attribuzioni sono nel branch"
                        + " experiment/zepp-native-music di antonyjr0/syncbeat. L'app abituale non"
                        + " viene sovrascritta.")
                .setPositiveButton("Chiudi", null)
                .setNeutralButton(
                    "Attribuzioni",
                    (d, w) -> showAssetText("Attribuzioni", "THIRD_PARTY_NOTICES.md"))
                .setNegativeButton("Licenza", (d, w) -> showAssetText("AGPL-3.0", "AGPL-3.0.txt"))
                .show());
  }

  private int dp(int n) {
    return (int) (n * getResources().getDisplayMetrics().density + .5f);
  }

  private TextView text(String s, int size, int color) {
    TextView t = new TextView(this);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    t.setPadding(0, dp(7), 0, dp(7));
    column.addView(t, new LinearLayout.LayoutParams(-1, -2));
    return t;
  }

  private void heading(String s, int size) {
    TextView t = text(s, size, Color.rgb(24, 58, 50));
    t.setTypeface(null, android.graphics.Typeface.BOLD);
  }

  private EditText field(String hint, boolean secret) {
    EditText e = new EditText(this);
    e.setHint(hint);
    e.setSingleLine(true);
    e.setTextSize(16);
    e.setInputType(
        secret
            ? InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
            : InputType.TYPE_CLASS_TEXT);
    e.setSaveEnabled(false);
    if (secret)
      e.setOnFocusChangeListener(
          (v, focus) -> {
            if (focus) getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
          });
    e.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);
    column.addView(e, new LinearLayout.LayoutParams(-1, dp(60)));
    return e;
  }

  private Button button(String s, View.OnClickListener l) {
    Button b = new Button(this);
    b.setText(s);
    b.setAllCaps(false);
    b.setMinHeight(dp(52));
    b.setOnClickListener(l);
    column.addView(b, new LinearLayout.LayoutParams(-1, -2));
    return b;
  }

  private void show(String s) {
    status.setText(s);
  }

  private void controls() {
    connect.setEnabled(!busy && !ready);
    upload.setEnabled(!busy && ready && mp3 != null);
    refresh.setEnabled(!busy && !ready);
    choose.setEnabled(!busy && !ready);
    devices.setEnabled(!busy && !ready);
    keyField.setEnabled(!busy && !ready);
    title.setEnabled(!busy && !ready);
    artist.setEnabled(!busy && !ready);
  }

  @SuppressWarnings("MissingPermission")
  private void loadDevices() {
    if (Build.VERSION.SDK_INT >= 31
        && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(new String[] {Manifest.permission.BLUETOOTH_CONNECT}, CONNECT_PERMISSION);
      return;
    }
    BluetoothManager manager = getSystemService(BluetoothManager.class);
    BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
    if (adapter == null || !adapter.isEnabled()) {
      show("Attiva Bluetooth dalle impostazioni Android, poi riprova.");
      return;
    }
    bonded.clear();
    List<String> labels = new ArrayList<>();
    labels.add("Seleziona esplicitamente l'orologio");
    try {
      for (BluetoothDevice d : adapter.getBondedDevices()) {
        bonded.add(d);
        String name = d.getName();
        String address = d.getAddress();
        labels.add(
            (name == null ? "Dispositivo senza nome" : name)
                + " · ..."
                + address.substring(Math.max(0, address.length() - 5)));
      }
    } catch (SecurityException e) {
      show("Permesso Bluetooth non disponibile.");
      return;
    }
    devices.setAdapter(
        new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, labels));
    show(
        bonded.isEmpty()
            ? "Nessun dispositivo abbinato. Non avviare reset o nuovi abbinamenti per questa prova."
            : "Seleziona il tuo Active 3 Premium. L'elenco da solo non prova compatibilita'.");
  }

  private void chooseFile() {
    Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    i.setType("audio/mpeg");
    i.addCategory(Intent.CATEGORY_OPENABLE);
    startActivityForResult(i, PICK);
  }

  @Override
  public void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request != PICK || result != RESULT_OK || data == null || data.getData() == null) return;
    final Uri uri = data.getData();
    if (mp3 != null) Arrays.fill(mp3, (byte) 0);
    mp3 = null;
    fileLabel.setText("Lettura del nuovo file...");
    busy = true;
    controls();
    show("Lettura MP3 locale...");
    final int run = generation;
    setDeadline(30, run);
    worker.execute(
        () -> {
          try (InputStream in = getContentResolver().openInputStream(uri);
              ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            if (in == null) throw new IOException("File non leggibile");
            synchronized (this) {
              if (run != generation) return;
              selectedInput = in;
            }
            byte[] block = new byte[8192];
            int n;
            while ((n = in.read(block)) >= 0) {
              if (n == 0) continue;
              if (out.size() + n > 32 * 1024 * 1024)
                throw new IOException("File oltre il limite di 32 MiB");
              out.write(block, 0, n);
            }
            byte[] loaded = out.toByteArray();
            Wire.require(
                loaded.length >= 3
                    && ((loaded[0] == 'I' && loaded[1] == 'D' && loaded[2] == '3')
                        || (loaded[0] & 255) == 255 && (loaded[1] & 0xe0) == 0xe0),
                "Non sembra un MP3: nessuna conversione automatica");
            runOnUiThread(
                () -> {
                  if (run != generation || isFinishing()) return;
                  mp3 = loaded;
                  clearDeadline();
                  busy = false;
                  fileLabel.setText(
                      "MP3 locale pronto: " + loaded.length + " byte. Controlla titolo e artista.");
                  show("File caricato. Nessun dato inviato all'orologio.");
                  controls();
                });
          } catch (Exception e) {
            finishError(run, e);
          }
        });
  }

  private void confirmConnection() {
    int index = devices.getSelectedItemPosition() - 1;
    if (index < 0 || index >= bonded.size()) {
      show("Prima scegli esplicitamente un dispositivo dall'elenco.");
      return;
    }
    if (mp3 == null) {
      show("Seleziona prima un MP3 locale, poi collegati.");
      return;
    }
    try {
      ZeppSession.validateMetadata(title.getText().toString());
      ZeppSession.validateMetadata(artist.getText().toString());
      Wire.require(title.length() > 0, "Inserisci un titolo");
    } catch (IOException e) {
      show(e.getMessage());
      return;
    }
    final BluetoothDevice device = bonded.get(index);
    new AlertDialog.Builder(this)
        .setTitle("Confermi il dispositivo?")
        .setMessage(
            "Dispositivo: "
                + devices.getSelectedItem()
                + "\n\n"
                + "Verra' contattato solo questo dispositivo. Assicurati che sia il tuo Active 3"
                + " Premium e che Zepp abbia finito la sincronizzazione. Questa fase autentica e"
                + " legge le capacita', senza inviare musica.")
        .setNegativeButton("Annulla", null)
        .setPositiveButton("Verifica", (d, w) -> startConnection(device))
        .show();
  }

  @SuppressWarnings("MissingPermission")
  private void startConnection(BluetoothDevice device) {
    char[] chars = new char[keyField.length()];
    keyField.getText().getChars(0, chars.length, chars, 0);
    keyField.setText("");
    final byte[] key;
    try {
      key = ZeppSession.parseKey(chars);
    } catch (IOException e) {
      show(e.getMessage());
      return;
    } finally {
      Arrays.fill(chars, '\0');
    }
    busy = true;
    ready = false;
    controls();
    int run = generation;
    setDeadline(120, run);
    show("Apertura connessione Classic...");
    worker.execute(
        () -> {
          try {
            BluetoothSocket candidate =
                device.createRfcommSocketToServiceRecord(UUID.fromString(ZeppSession.SERIAL_UUID));
            synchronized (this) {
              if (run != generation) {
                candidate.close();
                return;
              }
              socket = candidate;
            }
            candidate.connect();
            if (run != generation) {
              candidate.close();
              return;
            }
            ZeppSession session =
                new ZeppSession(
                    candidate.getInputStream(),
                    candidate.getOutputStream(),
                    new ZeppSession.Events() {
                      public void status(String s) {
                        runOnUiThread(
                            () -> {
                              if (run == generation) show(s);
                            });
                      }

                      public void progress(int done, int total) {
                        runOnUiThread(
                            () -> {
                              if (run == generation)
                                progress.setProgress((int) (100L * done / total));
                            });
                      }
                    });
            synchronized (this) {
              if (run != generation) {
                session.close();
                return;
              }
              client = session;
            }
            session.initialize(key);
            runOnUiThread(
                () -> {
                  if (run != generation) return;
                  clearDeadline();
                  busy = false;
                  ready = true;
                  setDeadline(300, run);
                  controls();
                });
          } catch (Exception e) {
            finishError(run, e);
          } finally {
            Arrays.fill(key, (byte) 0);
          }
        });
  }

  private void confirmUpload() {
    if (client == null || !ready || mp3 == null) return;
    new AlertDialog.Builder(this)
        .setTitle("Importare questo MP3?")
        .setMessage(
            "Titolo: "
                + title.getText()
                + "\nArtista: "
                + artist.getText()
                + "\nDimensione: "
                + mp3.length
                + " byte\n\n"
                + "Scrivera' un brano nel lettore originale. Non cancella altri file. Il prototipo"
                + " non offre cancellazione del brano importato: usa i controlli disponibili"
                + " dell'orologio/Zepp. Interrompere puo' lasciare un file parziale. Vuoi"
                + " procedere?")
        .setNegativeButton("Annulla", null)
        .setPositiveButton("Invia", (d, w) -> startUpload())
        .show();
  }

  private void startUpload() {
    final ZeppSession session = client;
    if (session == null) return;
    final int run = generation;
    final String t = title.getText().toString(), a = artist.getText().toString();
    busy = true;
    ready = false;
    controls();
    progress.setProgress(0);
    show("Trasferimento in corso. Tieni l'app in primo piano.");
    setDeadline(600, run);
    worker.execute(
        () -> {
          try {
            session.upload(mp3, t, a);
            runOnUiThread(
                () -> {
                  if (run != generation) return;
                  disconnect();
                  show(
                      "Ultimo blocco confermato. Verifica sul tuo orologio il titolo e la"
                          + " riproduzione nel lettore Musica. Poi verifica il ritorno a Zepp.");
                });
          } catch (Exception e) {
            finishError(run, e);
          }
        });
  }

  private void setDeadline(int seconds, int run) {
    clearDeadline();
    deadline =
        timer.schedule(
            () ->
                runOnUiThread(
                    () -> {
                      if (run == generation) {
                        disconnect();
                        show(
                            "Tempo massimo superato. Nessun tentativo automatico. Controlla"
                                + " l'orologio prima di riprovare.");
                      }
                    }),
            seconds,
            TimeUnit.SECONDS);
  }

  private void clearDeadline() {
    if (deadline != null) deadline.cancel(false);
    deadline = null;
  }

  private void finishError(int run, Exception e) {
    final String message =
        e instanceof IOException
            ? e.getMessage()
            : "Operazione non riuscita. Controlla permessi, Bluetooth e stato dell'orologio.";
    runOnUiThread(
        () -> {
          if (run != generation) return;
          disconnect();
          show("Interrotto: " + message + ". Nessun reset e nessun ritentativo automatico.");
        });
  }

  private synchronized void disconnect() {
    generation++;
    clearDeadline();
    ZeppSession c = client;
    client = null;
    InputStream selected = selectedInput;
    selectedInput = null;
    if (selected != null)
      try {
        selected.close();
      } catch (IOException ignored) {
      }
    BluetoothSocket s = socket;
    socket = null;
    if (s != null)
      try {
        s.close();
      } catch (IOException ignored) {
      }
    if (c != null) c.close();
    ready = false;
    busy = false;
    if (keyField != null) keyField.setText("");
    if (connect != null) controls();
  }

  private void showAssetText(String heading, String asset) {
    try {
      String license;
      try (InputStream in = getAssets().open(asset)) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] b = new byte[8192];
        int n;
        while ((n = in.read(b)) >= 0) out.write(b, 0, n);
        license = out.toString("UTF-8");
      }
      TextView t = new TextView(this);
      t.setText(license);
      t.setPadding(dp(16), dp(16), dp(16), dp(16));
      ScrollView s = new ScrollView(this);
      s.addView(t);
      new AlertDialog.Builder(this)
          .setTitle(heading)
          .setView(s)
          .setPositiveButton("Chiudi", null)
          .show();
    } catch (IOException e) {
      show("Testo disponibile nel file LICENSE del repository.");
    }
  }

  @Override
  public void onRequestPermissionsResult(int r, String[] p, int[] grants) {
    super.onRequestPermissionsResult(r, p, grants);
    if (r == CONNECT_PERMISSION) {
      if (grants.length > 0 && grants[0] == PackageManager.PERMISSION_GRANTED) loadDevices();
      else show("Permesso negato. Nessun collegamento avviato.");
    }
  }

  @Override
  public void onStop() {
    super.onStop();
    boolean active = socket != null || client != null;
    disconnect();
    if (active)
      show(
          "Connessione chiusa perche' l'app non e' piu' in primo piano. Controlla il brano"
              + " sull'orologio prima di riprovare.");
  }

  @Override
  public void onDestroy() {
    disconnect();
    worker.shutdownNow();
    timer.shutdownNow();
    if (mp3 != null) Arrays.fill(mp3, (byte) 0);
    super.onDestroy();
  }
}
