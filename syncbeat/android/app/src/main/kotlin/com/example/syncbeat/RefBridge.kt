/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Ponte Kotlin per il flusso di riferimento Zepp OS (confronto con ZeppBridge).
 * Canali: MethodChannel "syncbeat/zepp_ref" e EventChannel "syncbeat/zepp_ref/events".
 * Stessi metodi e argomenti del ponte principale (devices/run/cancel), cosi' sul
 * lato Dart il confronto e' un cambio di canale. Un solo tentativo per pressione,
 * nessun retry automatico, nessun fallback: stessi limiti del flusso principale.
 */
package com.example.syncbeat

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import com.example.syncbeat.zeppref.RefFlow
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class RefBridge(private val activity: MainActivity, private val publicAudio: PublicAudioBridge) {
    companion object { private const val REQUEST_CONNECT = 4207 }

    var events: EventChannel.EventSink? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val running = AtomicBoolean(false)
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var timedOut = false
    private var pendingDevices: MethodChannel.Result? = null

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        when (method) {
            "devices" -> devices(result)
            "run" -> run(args, result)
            "cancel" -> { closeSocket(); result.success(null) }
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
        timedOut = false
        worker.execute {
            val chars = keyText?.toCharArray() ?: CharArray(0)
            var key: ByteArray? = null
            var flow: RefFlow? = null
            try {
                val device = adapter()?.bondedDevices?.firstOrNull { it.address == address }
                    ?: throw IOException("Dispositivo non tra quelli abbinati. Scegli di nuovo l'orologio.")
                key = parseKey(chars)
                var data: ByteArray? = null
                if (send) {
                    if (title.isEmpty()) throw IOException("Titolo obbligatorio")
                    data = readFile(requireNotNull(path) { "File mancante" })
                }
                phase("0/8 Apertura connessione Classic (riferimento)")
                stopDiscovery()
                deadline = timer.schedule({ timedOut = true; closeSocket() }, timeout, TimeUnit.SECONDS)
                val connected = connectClassic(device)
                flow = RefFlow(connected.inputStream, connected.outputStream, object : RefFlow.Events {
                    override fun phase(text: String) = this@RefBridge.phase(text)
                    override fun progress(done: Int, total: Int) {
                        activity.runOnUiThread { events?.success(mapOf("type" to "progress", "done" to done, "total" to total)) }
                    }
                })
                flow.initialize(key)
                if (send) flow.upload(data!!, title, artist)
                activity.runOnUiThread { result.success(mapOf("sent" to send)) }
            } catch (error: Exception) {
                val message = when {
                    timedOut -> "Tempo massimo superato (flusso riferimento). Nessun tentativo automatico."
                    error is IOException -> error.message ?: "Errore Bluetooth"
                    else -> "Operazione non riuscita nel flusso di riferimento."
                }
                android.util.Log.w("SyncBeatZeppRef", "Interrotto: ${error.javaClass.simpleName}")
                activity.runOnUiThread { result.error("ZEPP_REF", message, null) }
            } finally {
                chars.fill('\u0000')
                key?.fill(0)
                deadline?.cancel(false)
                try { flow?.close() } catch (_: Exception) {}
                closeSocket()
                running.set(false)
            }
        }
    }

    private fun parseKey(chars: CharArray): ByteArray {
        var text = String(chars).trim()
        if (text.startsWith("0x") || text.startsWith("0X")) text = text.substring(2)
        if (!Regex("[0-9a-fA-F]{32}").matches(text)) throw IOException("Chiave Zepp non valida")
        return ByteArray(16) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    private fun readFile(path: String): ByteArray {
        val input: InputStream =
            if (path.startsWith("content://")) publicAudio.openInput(path)
            else YoutubeRequestPolicy.requirePrivate(File(path), listOf(activity.filesDir, activity.cacheDir)).inputStream()
        input.use {
            val data = it.readBytes()
            if (data.size > 32 * 1024 * 1024) throw IOException("Il file supera il limite di 32 MiB di questa prova.")
            return data
        }
    }

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

    /** Un solo tentativo: socket standard sul servizio Zepp (UUID 00000022-...), come i riferimenti. */
    @Suppress("MissingPermission")
    private fun connectClassic(device: BluetoothDevice): BluetoothSocket {
        val started = System.currentTimeMillis()
        try {
            val candidate = device.createRfcommSocketToServiceRecord(UUID.fromString(RefFlow.SERIAL_UUID))
            socket = candidate
            candidate.connect()
            android.util.Log.i("SyncBeatZeppRef", "Classic connesso in ${System.currentTimeMillis() - started} ms")
            return candidate
        } catch (error: Exception) {
            android.util.Log.w("SyncBeatZeppRef", "Classic fallito dopo ${System.currentTimeMillis() - started} ms: ${error.javaClass.simpleName}")
            closeSocket()
            throw IOException("Connessione Classic fallita (${error.javaClass.simpleName}) dopo ${System.currentTimeMillis() - started} ms")
        }
    }

    private fun closeSocket() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }

    private fun phase(text: String) {
        android.util.Log.i("SyncBeatZeppRef", text)
        activity.runOnUiThread { events?.success(mapOf("type" to "status", "text" to text)) }
    }
}
