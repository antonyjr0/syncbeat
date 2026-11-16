package com.example.syncbeat

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
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
 * non viene salvata ne' registrata nei log.
 */
class ZeppBridge(private val activity: Activity, private val publicAudio: PublicAudioBridge) {
    @Volatile var events: EventChannel.EventSink? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val running = AtomicBoolean(false)
    @Volatile private var socket: BluetoothSocket? = null
    private var pendingDevices: MethodChannel.Result? = null

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        when (method) {
            "devices" -> devices(result)
            "run" -> run(args, result)
            "secure" -> {
                val enabled = args["enabled"] == true
                activity.runOnUiThread {
                    val flag = android.view.WindowManager.LayoutParams.FLAG_SECURE
                    if (enabled) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
                }
                result.success(null)
            }
            "cancel" -> { closeSocket(); result.success(null) }
            "licenses" -> result.success(
                listOf("AGPL-3.0.txt", "tiny-ECDH-LICENSE.txt", "THIRD_PARTY_NOTICES.md").joinToString("\n\n") { name ->
                    activity.assets.open("licenses/zepp/$name").bufferedReader().use { it.readText() }
                }
            )
            else -> result.notImplemented()
        }
    }

    private fun hasPermission() =
        Build.VERSION.SDK_INT < 31 ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun adapter(): BluetoothAdapter? =
        activity.getSystemService(BluetoothManager::class.java)?.adapter

    private fun devices(result: MethodChannel.Result) {
        if (!hasPermission()) {
            pendingDevices?.error("CANCELLED", "Richiesta permesso sostituita", null)
            pendingDevices = result
            activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_CONNECT)
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
        var deadline: ScheduledFuture<*>? = null
        var timedOut = false
        worker.execute {
            val chars = keyText?.toCharArray() ?: CharArray(0)
            var key: ByteArray? = null
            var session: ZeppSession? = null
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
                status("Apertura connessione Classic...")
                val candidate = device.createRfcommSocketToServiceRecord(UUID.fromString(ZeppSession.SERIAL_UUID))
                socket = candidate
                deadline = timer.schedule({ timedOut = true; closeSocket() }, timeout, TimeUnit.SECONDS)
                candidate.connect()
                session = ZeppSession(candidate.inputStream, candidate.outputStream, object : ZeppSession.Events {
                    override fun status(text: String) = this@ZeppBridge.status(text)
                    override fun progress(acknowledgedBytes: Int, total: Int) {
                        activity.runOnUiThread { events?.success(mapOf("type" to "progress", "done" to acknowledgedBytes, "total" to total)) }
                    }
                })
                session.initialize(key)
                if (send) session.upload(data!!, title, artist)
                val sent = send
                activity.runOnUiThread { result.success(mapOf("sent" to sent)) }
            } catch (error: Exception) {
                val message = when {
                    timedOut -> "Tempo massimo superato. Nessun tentativo automatico: controlla l'orologio prima di riprovare."
                    error is IOException -> error.message ?: "Errore Bluetooth"
                    else -> "Operazione non riuscita. Controlla permessi, Bluetooth e stato dell'orologio."
                }
                android.util.Log.w("SyncBeatZepp", "Operazione interrotta: ${error.javaClass.simpleName}")
                activity.runOnUiThread { result.error("ZEPP", message, null) }
            } finally {
                chars.fill('\u0000')
                key?.fill(0)
                deadline?.cancel(false)
                try { session?.close() } catch (_: Exception) {}
                closeSocket()
                running.set(false)
            }
        }
    }

    private fun status(text: String) = activity.runOnUiThread { events?.success(mapOf("type" to "status", "text" to text)) }

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
