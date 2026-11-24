package com.example.syncbeat

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import android.os.SystemClock
import android.util.Log
import com.example.syncbeat.zepp.ZeppSession
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Esperimento: invio di un MP3 al lettore Musica di un orologio Zepp OS via
 * Bluetooth Classic. Ogni operazione e' esplicita (dispositivo scelto dall'utente,
 * una sola alla volta, nessun ritentativo automatico). La chiave di abbinamento
 * resta nell'archivio sicuro Flutter e non viene registrata nei log nativi.
 */
class ZeppBridge(private val activity: Activity, private val publicAudio: PublicAudioBridge) {
    @Volatile var events: EventChannel.EventSink? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val running = AtomicBoolean(false)
    @Volatile private var diagnosticPhase = "idle"
    @Volatile private var diagnosticOutcome = "none"
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var timedOutFlag = false
    private var pendingDevices: MethodChannel.Result? = null
    private var bleProbe: ZeppBleProbe? = null
    private val cancelled = AtomicBoolean(false)
    private val adbPairing = AdbPairingNotification(activity)
    private val adbDiscovery = AdbConnectDiscovery(activity)
    private lateinit var adbChannel: MethodChannel
    fun configureAdb(messenger: io.flutter.plugin.common.BinaryMessenger) {
        adbChannel = MethodChannel(messenger, "syncbeat/embedded_adb")
        adbChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureWirelessDebug" -> {
                    try {
                        val preparation = WirelessDebugPreparation(object : WirelessDebugPreparation.Device {
                            override fun wifiConnected(): Boolean {
                                val connectivity = activity.getSystemService(ConnectivityManager::class.java)
                                @Suppress("DEPRECATION")
                                return connectivity.allNetworks.any {
                                    connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                                }
                            }
                            override fun mayWriteSecureSettings() = activity.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
                            override fun enabled() = Settings.Global.getInt(activity.contentResolver, "adb_wifi_enabled", 0) == 1
                            override fun enable() = Settings.Global.putInt(activity.contentResolver, "adb_wifi_enabled", 1)
                        })
                        result.success(preparation.prepare())
                    } catch (_: Exception) {
                        result.error("ADB_WIFI_ENABLE_FAILED", "Attivazione Debug wireless non riuscita. Usa le impostazioni Android.", null)
                    }
                }
                "discoverConnect" -> adbDiscovery.discover(result)
                "pairFromNotification" -> adbPairing.start(result)
                "cancelPairingNotification" -> { adbPairing.cancel(); result.success(null) }
                "bootstrap" -> result.success(mapOf("apkPath" to activity.applicationInfo.sourceDir,
                    "user" to android.os.Process.myUid() / 100000))
                "leaseLost" -> { ZeppDiagnostics.record("BRIDGE_LEASE_LOST"); cancelled.set(true); closeSocket(); result.success(null) }
                "settings" -> {
                    try {
                        openWirelessDebuggingSettings(activity)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("SETTINGS", "Apri Debug wireless dalle impostazioni Android.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun closePairingNotification() = adbPairing.cancel()
    private val coordination by lazy { ZeppAdbCoordinator(activity, adbChannel).also {
        it.onHelperLost = { cancelled.set(true); closeSocket() }
    } }

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        when (method) {
            "devices" -> devices(result)
            "run" -> run(args, result)
            "probeBle" -> probeBle(args, result)
            "adbStatus" -> worker.execute {
                try {
                    // Observation must never restore permissions or bootstrap a helper.
                    val state = coordination.status() + mapOf("phase" to diagnosticPhase, "outcome" to diagnosticOutcome)
                    activity.runOnUiThread { result.success(state) }
                } catch (error: Exception) {
                    activity.runOnUiThread { result.error((error as? ZeppCoordinationException)?.code ?: "RESTORE", error.message, null) }
                }
            }
            "authorizeAdb" -> worker.execute {
                try { val ready = coordination.status()["state"] == "ready"; activity.runOnUiThread { result.success(ready) } }
                catch (_: Exception) { activity.runOnUiThread { result.success(false) } }
            }
            "setZeppCoordination" -> {
                worker.execute {
                    try { coordination.setEnabled(args["enabled"] == true); activity.runOnUiThread { result.success(null) } }
                    catch (error: Exception) { activity.runOnUiThread { result.error("ADB", error.message, null) } }
                }
            }
            "prepareZeppHelper", "restoreZeppPermissions", "testZeppPermissions" -> {
                if (!running.compareAndSet(false, true)) result.error("BUSY", "Un’operazione è già in corso.", null)
                else worker.execute {
                    val started = SystemClock.elapsedRealtime()
                    Log.i("SyncBeatZepp", "$method avviato")
                    try {
                        when (method) {
                            "prepareZeppHelper" -> coordination.prepare()
                            "testZeppPermissions" -> coordination.testCycle()
                            else -> coordination.restore()
                        }
                        Log.i("SyncBeatZepp", "$method riuscito in ${SystemClock.elapsedRealtime() - started} ms")
                        activity.runOnUiThread { result.success(null) }
                    } catch (error: Exception) {
                        Log.w("SyncBeatZepp", "$method fallito dopo ${SystemClock.elapsedRealtime() - started} ms: ${error.javaClass.simpleName}")
                        activity.runOnUiThread { result.error((error as? ZeppCoordinationException)?.code ?: "RESTORE", error.message, null) }
                    } finally { running.set(false) }
                }
            }
            "openZepp" -> {
                if (running.get()) {
                    result.error("BUSY", "Attendi la fine dell’operazione diretta prima di aprire Zepp.", null)
                } else {
                    val launch = activity.packageManager.getLaunchIntentForPackage("com.huami.watch.hmwatchmanager")
                    if (launch == null) result.error("ZEPP_MISSING", "Zepp non è installata o non è disponibile su questo telefono.", null)
                    else {
                        try { activity.startActivity(launch); result.success(null) }
                        catch (_: Exception) { result.error("ZEPP_LAUNCH", "Impossibile aprire Zepp. Aprila dall’elenco delle app.", null) }
                    }
                }
            }
            "secure" -> {
                val enabled = args["enabled"] == true
                activity.runOnUiThread {
                    val flag = android.view.WindowManager.LayoutParams.FLAG_SECURE
                    if (enabled) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
                }
                result.success(null)
            }
            "cancel" -> { ZeppDiagnostics.record("BRIDGE_CANCEL"); cancelled.set(true); bleProbe?.cancel(); closeSocket(); result.success(null) }
            "licenses" -> result.success(
                listOf("AGPL-3.0.txt", "tiny-ECDH-LICENSE.txt", "THIRD_PARTY_NOTICES.md", "flutter_adb-LICENSE.txt").joinToString("\n\n") { name ->
                    activity.assets.open("licenses/zepp/$name").bufferedReader().use { it.readText() }
                }
            )
            else -> result.notImplemented()
        }
    }

    @Suppress("MissingPermission")
    private fun probeBle(args: Map<String, Any?>, result: MethodChannel.Result) {
        if (!hasPermission()) {
            Log.w("SyncBeatZepp", "Sonda BLE: permesso Bluetooth non disponibile")
            result.error("PERMISSION", "Permesso Bluetooth non disponibile.", null)
            return
        }
        if (!running.compareAndSet(false, true)) {
            Log.w("SyncBeatZepp", "Sonda BLE: operazione già in corso")
            result.error("BUSY", "Un’operazione è già in corso.", null)
            return
        }
        val started = SystemClock.elapsedRealtime()
        Log.i("SyncBeatZepp", "Sonda BLE avviata (limite 20 secondi)")
        try {
            val device = adapter()?.bondedDevices?.firstOrNull { it.address == args["address"] }
            if (device == null) {
                running.set(false)
                Log.w("SyncBeatZepp", "Sonda BLE: orologio abbinato non selezionato")
                result.error("DEVICE", "Scegli un orologio già abbinato.", null)
                return
            }
            bleProbe = ZeppBleProbe(activity) { characteristics, error ->
                running.set(false)
                bleProbe = null
                val elapsed = SystemClock.elapsedRealtime() - started
                // ZeppBleProbe supplies fixed messages and numeric GATT status only.
                if (error != null) {
                    Log.w("SyncBeatZepp", "Sonda BLE fallita dopo $elapsed ms: $error")
                    result.error("BLE_PROBE", error, null)
                } else {
                    Log.i("SyncBeatZepp", "Sonda BLE riuscita in $elapsed ms: ${characteristics?.size ?: 0} caratteristiche")
                    result.success(characteristics)
                }
            }
            bleProbe!!.start(device)
        } catch (error: Exception) {
            running.set(false)
            bleProbe = null
            Log.w("SyncBeatZepp", "Sonda BLE non avviata: ${error.javaClass.simpleName}")
            result.error("BLE_PROBE", "Verifica BLE non disponibile.", null)
        }
    }

    private fun hasPermission() =
        Build.VERSION.SDK_INT < 31 ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun adapter(): BluetoothAdapter? =
        activity.getSystemService(BluetoothManager::class.java)?.adapter

    private fun scanAsked() =
        Build.VERSION.SDK_INT < 31 ||
            activity.getSharedPreferences("zepp_bridge", 0).getBoolean("scan_asked", false)

    private fun devices(result: MethodChannel.Result) {
        if (!hasPermission() || !scanAsked()) {
            activity.getSharedPreferences("zepp_bridge", 0).edit().putBoolean("scan_asked", true).apply()
            pendingDevices?.error("CANCELLED", "Richiesta permesso sostituita", null)
            pendingDevices = result
            // BLUETOOTH_SCAN serve solo a fermare una ricerca in corso (cancelDiscovery); se negato si prosegue.
            activity.requestPermissions(
                if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
                else arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                REQUEST_CONNECT,
            )
            return
        }
        listDevices(result)
    }

    @Suppress("MissingPermission")
    private fun listDevices(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Attiva il Bluetooth dalle impostazioni Android, poi riprova.", null)
            return
        }
        try {
            result.success(adapter.bondedDevices.map {
                mapOf("name" to (it.name ?: "Dispositivo senza nome"), "address" to it.address)
            })
        } catch (_: SecurityException) {
            result.error("PERMISSION", "Permesso Bluetooth non disponibile.", null)
        }
    }

    fun onRequestPermissionsResult(code: Int, grants: IntArray): Boolean {
        if (adbPairing.onPermissionResult(code, grants)) return true
        if (code != REQUEST_CONNECT) return false
        val result = pendingDevices ?: return true
        pendingDevices = null
        if (grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED) listDevices(result)
        else result.error("PERMISSION", "Permesso Bluetooth negato. Puoi concederlo dalle impostazioni dell'app.", null)
        return true
    }

    @Suppress("MissingPermission")
    private fun run(args: Map<String, Any?>, result: MethodChannel.Result) {
        if (!hasPermission()) { result.error("PERMISSION", "Permesso Bluetooth non disponibile.", null); return }
        if (!running.compareAndSet(false, true)) { result.error("BUSY", "Un'operazione e' gia' in corso.", null); return }
        val address = args["address"] as? String
        val keyText = args["key"] as? String
        val send = args["send"] == true
        val path = args["path"] as? String
        val title = args["title"] as? String ?: ""
        val artist = args["artist"] as? String ?: ""
        val timeout = if (send) 720L else 120L
        val coordinateZepp = args["coordinateZepp"] == true
        var deadline: ScheduledFuture<*>? = null
        timedOutFlag = false
        cancelled.set(false)
        worker.execute {
            val started = SystemClock.elapsedRealtime()
            val operation = if (send) "Invio MP3" else "Verifica Classic"
            Log.i("SyncBeatZepp", "$operation avviata: gestione Zepp=$coordinateZepp")
            var phase = "preparazione"
            diagnosticPhase = "preparation"
            diagnosticOutcome = "running"
            ZeppDiagnostics.record("RUN_START")
            val chars = keyText?.toCharArray() ?: CharArray(0)
            var key: ByteArray? = null
            var session: ZeppSession? = null
            var completed = false
            var failure: String? = null
            try {
                val device = adapter()?.bondedDevices?.firstOrNull { it.address == address }
                    ?: throw IOException("Dispositivo non tra quelli abbinati. Scegli di nuovo l'orologio.")
                key = ZeppSession.parseKey(chars)
                var data: ByteArray? = null
                if (send) {
                    ZeppSession.validateMetadata(title)
                    ZeppSession.validateMetadata(artist)
                    if (title.isEmpty()) throw IOException("Titolo obbligatorio")
                    data = readMp3(requireNotNull(path) { "File mancante" })
                }
                deadline = timer.schedule({ timedOutFlag = true; closeSocket() }, timeout, TimeUnit.SECONDS)
                if (coordinateZepp) {
                    phase = "sospensione Zepp"
                    diagnosticPhase = "suspend"
                    ZeppDiagnostics.record("RUN_SUSPEND")
                    status("Sospensione temporanea di Dispositivi nelle vicinanze per Zepp…")
                    coordination.begin((timeout + 60) * 1000)
                    Thread.sleep(500) // Allow Android to close Zepp's existing sockets.
                }
                if (cancelled.get() || timedOutFlag) throw IOException("Operazione annullata prima del collegamento.")
                phase = "connessione Classic"
                diagnosticPhase = "connect"
                ZeppDiagnostics.record("RUN_CONNECT")
                status("Apertura connessione Classic...")
                stopDiscovery()
                val candidate = connectClassic(device)
                session = ZeppSession(candidate.inputStream, candidate.outputStream, object : ZeppSession.Events {
                    override fun status(text: String) = this@ZeppBridge.status(text)
                    override fun progress(acknowledgedBytes: Int, total: Int) {
                        activity.runOnUiThread { events?.success(mapOf("type" to "progress", "done" to acknowledgedBytes, "total" to total)) }
                    }
                })
                if (cancelled.get()) throw IOException("Operazione annullata.")
                phase = "inizializzazione sessione"
                diagnosticPhase = "initialize"
                ZeppDiagnostics.record("RUN_INITIALIZE")
                session.initialize(key)
                if (cancelled.get()) throw IOException("Operazione annullata.")
                if (send) {
                    phase = "importazione MP3"
                    diagnosticPhase = "upload"
                    ZeppDiagnostics.record("RUN_UPLOAD")
                    session.upload(data!!, title, artist)
                }
                completed = true
            } catch (error: Exception) {
                ZeppDiagnostics.record("RUN_PRIMARY_ERROR", "cancelled=${cancelled.get()} timedOut=$timedOutFlag")
                val message = when {
                    timedOutFlag -> "Tempo massimo superato. Nessun tentativo automatico: controlla l'orologio prima di riprovare."
                    error is IOException -> error.message ?: "Errore Bluetooth"
                    else -> "Operazione non riuscita. Controlla permessi, Bluetooth e stato dell'orologio."
                }
                val reason = when {
                    timedOutFlag -> "tempo massimo superato"
                    cancelled.get() -> "annullata"
                    else -> error.javaClass.simpleName
                }
                val rejection = Regex("^Importazione rifiutata dall'orologio \\(codice ([0-9]{1,3})\\)")
                    .find(message)?.groupValues?.get(1)
                val detail = rejection?.let { ", codice importazione=$it" }.orEmpty()
                Log.w("SyncBeatZepp", "Operazione interrotta: $reason, fase=$phase$detail")
                failure = message
            } finally {
                ZeppDiagnostics.record("RUN_FINALLY", "completed=$completed primaryFailed=${failure != null}")
                chars.fill('\u0000')
                key?.fill(0)
                deadline?.cancel(false)
                try { session?.close() } catch (_: Exception) {}
                closeSocket()
                if (coordinateZepp) {
                    diagnosticPhase = "restore"
                    status("Ripristino di Dispositivi nelle vicinanze per Zepp…")
                    try {
                        coordination.restore(allowBootstrap = false)
                        android.util.Log.i("SyncBeatZepp", "Zepp Nearby devices permissions restored")
                        if (failure != null) failure += "\nDispositivi nelle vicinanze di Zepp ripristinato allo stato iniziale."
                    } catch (error: Exception) {
                        ZeppDiagnostics.record("RUN_RECOVERY_ERROR")
                        Log.w("SyncBeatZepp", "Ripristino Zepp non confermato: ${error.javaClass.simpleName}")
                        failure = listOfNotNull(failure, error.message ?: "Ripristino Zepp non confermato.").joinToString("\n")
                    }
                }
                running.set(false)
            }
            val error = failure
            val outcome = if (completed && error == null) "riuscita" else "fallita"
            diagnosticOutcome = if (completed && error == null) "success" else "failed"
            Log.i("SyncBeatZepp", "$operation $outcome dopo ${SystemClock.elapsedRealtime() - started} ms")
            activity.runOnUiThread {
                if (completed && error == null) result.success(mapOf("sent" to send, "zeppRestored" to coordinateZepp))
                else result.error("ZEPP", error ?: "Operazione interrotta.", null)
            }
        }
    }


    /**
     * Ferma una eventuale ricerca Bluetooth in corso prima di connettersi
     * (come fanno Gadgetbridge e OronBox). Se il permesso di scansione manca
     * si prosegue comunque.
     */
    @Suppress("MissingPermission")
    private fun stopDiscovery() {
        if (Build.VERSION.SDK_INT >= 31 &&
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED
        ) return
        try {
            val a = adapter()
            if (a != null && a.isDiscovering) a.cancelDiscovery()
        } catch (_: SecurityException) {
        }
    }

    /**
     * Un solo tentativo esplicito per pressione, come prima: socket standard sul
     * servizio Zepp (UUID 00000022-...), la stessa scelta di Gadgetbridge. Nessun
     * fallback automatico (insecure, canali, removeBond). Nei log e nel messaggio
     * finiscono solo tipo di eccezione e millisecondi, mai chiavi o indirizzi.
     */
    @Suppress("MissingPermission")
    private fun connectClassic(device: BluetoothDevice): BluetoothSocket {
        val started = System.currentTimeMillis()
        try {
            val candidate = device.createRfcommSocketToServiceRecord(UUID.fromString(ZeppSession.SERIAL_UUID))
            socket = candidate
            candidate.connect()
            android.util.Log.i("SyncBeatZepp", "Classic connesso in ${System.currentTimeMillis() - started} ms")
            return candidate
        } catch (error: Exception) {
            val elapsed = System.currentTimeMillis() - started
            android.util.Log.w("SyncBeatZepp", "Classic fallito dopo $elapsed ms: ${error.javaClass.simpleName}")
            closeSocket()
            if (timedOutFlag) throw IOException("Tempo massimo superato.")
            throw IOException("Connessione Classic non riuscita (${error.javaClass.simpleName} dopo $elapsed ms: ${error.message ?: "senza dettaglio"}). Nessun tentativo automatico: controlla l'orologio prima di riprovare.")
        }
    }

    private fun status(text: String) {
        // Status text is emitted by the bridge and protocol state machine, never by the file or device.
        Log.i("SyncBeatZepp", text)
        activity.runOnUiThread { events?.success(mapOf("type" to "status", "text" to text)) }
    }

    private fun closeSocket() {
        val s = socket
        socket = null
        try { s?.close() } catch (_: IOException) {}
    }

    private fun readMp3(path: String): ByteArray {
        val input: InputStream =
            if (path.startsWith("content://")) publicAudio.openInput(path)
            else YoutubeRequestPolicy.requirePrivate(File(path), listOf(activity.filesDir, activity.cacheDir)).inputStream()
        input.use {
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                out.write(buffer, 0, count)
                if (out.size() > MAX_BYTES) throw IOException("Il file supera il limite di 32 MiB di questa prova.")
            }
            if (out.size() == 0) throw IOException("File vuoto")
            return out.toByteArray()
        }
    }

    companion object {
        const val REQUEST_CONNECT = 4210
        const val MAX_BYTES = 32 * 1024 * 1024
    }
}
