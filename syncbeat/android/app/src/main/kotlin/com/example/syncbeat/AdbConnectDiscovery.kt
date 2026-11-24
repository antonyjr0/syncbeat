package com.example.syncbeat

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface

/** Platform adapter only. Dart selects a self-device candidate and connects once. */
@Suppress("DEPRECATION")
internal class AdbConnectDiscovery(context: Context) {
    private val manager = context.getSystemService(NsdManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var running = false

    fun discover(result: MethodChannel.Result) {
        if (running) { result.error("ADB_DISCOVERY_BUSY", "Ricerca già in corso.", null); return }
        if (Build.VERSION.SDK_INT < 30) {
            result.error("ADB_DISCOVERY_UNSUPPORTED", "Serve Android 11 o successivo.", null); return
        }
        val local = try {
            NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .filter { !it.isLoopbackAddress && !it.isAnyLocalAddress && !it.isMulticastAddress }
                .mapNotNull { it.hostAddress?.substringBefore('%') }.distinct()
        } catch (_: Exception) {
            result.error("ADB_DISCOVERY_NETWORK", "Indirizzi locali non disponibili.", null); return
        }
        running = true
        var finished = false
        var started = false
        var stopped = false
        var stopRequested = false
        var windowEnded = false
        var resolving = false
        var resolutionFailed = false
        val known = mutableSetOf<String>()
        val lost = mutableSetOf<String>()
        val queue = java.util.ArrayDeque<NsdServiceInfo>()
        val resolved = linkedMapOf<String, Map<String, Any>>()
        lateinit var listener: NsdManager.DiscoveryListener
        lateinit var window: Runnable
        lateinit var deadline: Runnable

        fun stop() {
            if (started && !stopped && !stopRequested) {
                stopRequested = true
                runCatching { manager.stopServiceDiscovery(listener) }
            }
        }
        fun finish(code: String? = null) {
            if (finished) return
            finished = true
            running = false
            main.removeCallbacks(window); main.removeCallbacks(deadline)
            stop()
            if (code != null) result.error(code, "Ricerca Debug wireless non riuscita. Controlla Wi-Fi e autorizzazione Android.", null)
            else {
                ZeppDiagnostics.record("NSD_DISCOVERY_SNAPSHOT", "local=${local.size} services=${resolved.size}")
                result.success(mapOf("localAddresses" to local, "services" to resolved.values.toList()))
            }
        }
        fun completeIfReady() {
            if (windowEnded && stopped && !resolving && queue.isEmpty()) {
                finish(if (resolutionFailed) "ADB_DISCOVERY_INCOMPLETE" else null)
            }
        }
        fun resolveNext() {
            if (finished || resolving) return
            while (queue.isNotEmpty() && queue.peek().serviceName in lost) queue.remove()
            if (queue.isEmpty()) { completeIfReady(); return }
            val item = queue.remove()
            resolving = true
            try {
                manager.resolveService(item, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) { main.post {
                        if (finished) return@post
                        resolving = false
                        if (item.serviceName !in lost) resolutionFailed = true
                        resolveNext()
                    } }
                    override fun onServiceResolved(info: NsdServiceInfo) { main.post {
                        if (finished) return@post
                        resolving = false
                        if (item.serviceName !in lost) {
                            val hosts = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
                            resolved[item.serviceName] = mapOf("name" to info.serviceName,
                                "type" to info.serviceType, "port" to info.port,
                                "addresses" to hosts.mapNotNull { it.hostAddress?.substringBefore('%') })
                        }
                        resolveNext()
                    } }
                })
            } catch (_: Exception) { resolving = false; finish("ADB_DISCOVERY_RESOLVE_FAILED") }
        }
        window = Runnable { windowEnded = true; stop(); completeIfReady() }
        deadline = Runnable { finish("ADB_DISCOVERY_TIMEOUT") }
        listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) { main.post {
                started = true
                if (finished) stop() else main.postDelayed(window, 5_000)
            } }
            override fun onServiceFound(info: NsdServiceInfo) { main.post {
                val type = info.serviceType.lowercase(java.util.Locale.ROOT).trim('.').removeSuffix(".local")
                if (finished || windowEnded || type != TYPE) return@post
                lost.remove(info.serviceName)
                if (!known.add(info.serviceName)) return@post
                ZeppDiagnostics.record("NSD_DISCOVERY_FOUND", "count=${known.size}")
                if (known.size > 32) { finish("ADB_DISCOVERY_AMBIGUOUS"); return@post }
                queue.add(info); resolveNext()
            } }
            override fun onServiceLost(info: NsdServiceInfo) { main.post {
                lost.add(info.serviceName); resolved.remove(info.serviceName); known.remove(info.serviceName)
            } }
            override fun onDiscoveryStopped(type: String) { main.post {
                stopped = true
                if (!finished && !windowEnded) finish("ADB_DISCOVERY_INTERRUPTED") else completeIfReady()
            } }
            override fun onStartDiscoveryFailed(type: String, errorCode: Int) { main.post { finish("ADB_DISCOVERY_FAILED") } }
            override fun onStopDiscoveryFailed(type: String, errorCode: Int) { main.post { finish("ADB_DISCOVERY_STOP_FAILED") } }
        }
        main.postDelayed(deadline, 10_000)
        try { manager.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (_: Exception) { finish("ADB_DISCOVERY_FAILED") }
    }

    companion object { const val TYPE = "_adb-tls-connect._tcp" }
}
