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
        val entries = AdbDiscoveryEntries()
        val queue = java.util.ArrayDeque<NsdServiceInfo>()
        val tracking = mutableMapOf<String, NsdManager.ServiceInfoCallback>()
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
            if (Build.VERSION.SDK_INT >= 34) {
                tracking.values.toList().forEach { callback ->
                    runCatching { manager.unregisterServiceInfoCallback(callback) }
                }
                tracking.clear()
            }
            if (code != null) result.error(code, "Ricerca Debug wireless non riuscita. Controlla Wi-Fi e autorizzazione Android.", null)
            else {
                ZeppDiagnostics.record("NSD_DISCOVERY_SNAPSHOT", "local=${local.size} services=${entries.resolvedCount}")
                result.success(mapOf("localAddresses" to local, "services" to entries.snapshot()))
            }
        }
        fun completeIfReady() {
            if (windowEnded && stopped && !resolving && queue.isEmpty() && !entries.pendingResolution) {
                finish(if (entries.resolutionFailed) "ADB_DISCOVERY_INCOMPLETE" else null)
            }
        }
        fun snapshot(info: NsdServiceInfo): Map<String, Any> {
            val hosts = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
            return mapOf("name" to info.serviceName, "type" to info.serviceType, "port" to info.port,
                "addresses" to hosts.mapNotNull { it.hostAddress?.substringBefore('%') })
        }
        fun track(info: NsdServiceInfo, ticket: AdbDiscoveryEntries.Ticket) {
            if (Build.VERSION.SDK_INT < 34) return
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) { main.post {
                    if (finished || entries.ticket(ticket.name) != ticket) return@post
                    tracking.remove(ticket.name); entries.fail(ticket); completeIfReady()
                } }
                override fun onServiceUpdated(updated: NsdServiceInfo) { main.post {
                    if (finished) return@post
                    if (entries.update(ticket, snapshot(updated))) {
                        ZeppDiagnostics.record("NSD_SERVICE_UPDATED", "count=${entries.resolvedCount}")
                    }
                    completeIfReady()
                } }
                override fun onServiceLost() { main.post {
                    if (finished || entries.ticket(ticket.name) != ticket) return@post
                    // Keep registration until discovery loses this instance: a later
                    // update can carry its new port. Invalidate the old value now.
                    entries.invalidate(ticket)
                    completeIfReady()
                } }
                override fun onServiceInfoCallbackUnregistered() { main.post {
                    if (finished || entries.ticket(ticket.name) != ticket) return@post
                    tracking.remove(ticket.name); entries.fail(ticket); completeIfReady()
                } }
            }
            tracking[info.serviceName] = callback
            try { manager.registerServiceInfoCallback(info, mainExecutor, callback) }
            catch (_: Exception) { tracking.remove(info.serviceName); entries.fail(ticket) }
        }
        fun resolveNext() {
            if (finished || resolving) return
            while (queue.isNotEmpty() && entries.ticket(queue.peek().serviceName) == null) queue.remove()
            if (queue.isEmpty()) { completeIfReady(); return }
            val item = queue.remove()
            val ticket = entries.ticket(item.serviceName) ?: return
            resolving = true
            try {
                manager.resolveService(item, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) { main.post {
                        if (finished) return@post
                        resolving = false
                        entries.fail(ticket)
                        resolveNext()
                    } }
                    override fun onServiceResolved(info: NsdServiceInfo) { main.post {
                        if (finished) return@post
                        resolving = false
                        entries.update(ticket, snapshot(info))
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
                val ticket = entries.found(info.serviceName) ?: return@post
                ZeppDiagnostics.record("NSD_DISCOVERY_FOUND", "count=${entries.size}")
                if (entries.size > 32) { finish("ADB_DISCOVERY_AMBIGUOUS"); return@post }
                if (Build.VERSION.SDK_INT >= 34) track(info, ticket)
                else { queue.add(info); resolveNext() }
            } }
            override fun onServiceLost(info: NsdServiceInfo) { main.post {
                entries.lost(info.serviceName)
                if (Build.VERSION.SDK_INT >= 34) {
                    tracking.remove(info.serviceName)?.let { runCatching { manager.unregisterServiceInfoCallback(it) } }
                }
                completeIfReady()
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

    private val mainExecutor = java.util.concurrent.Executor { command -> main.post(command) }

    companion object { const val TYPE = "_adb-tls-connect._tcp" }
}
