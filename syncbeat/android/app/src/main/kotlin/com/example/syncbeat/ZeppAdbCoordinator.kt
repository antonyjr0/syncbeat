package com.example.syncbeat

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

internal class ZeppCoordinationException(val code: String, message: String) : IOException(message)

/** Dart owns the flutter_adb connection; native finally still owns rollback. */
internal class ZeppAdbCoordinator(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val preferences = activity.getSharedPreferences("zepp_bridge", 0)
    var onHelperLost: (() -> Unit)? = null

    private fun call(method: String, value: Any? = null): Any? {
        val latch = CountDownLatch(1)
        var result: Any? = null
        var failure: ZeppCoordinationException? = null
        ZeppDiagnostics.record("COORDINATOR_CALL", "method=$method")
        main.post {
            channel.invokeMethod(method, value, object : MethodChannel.Result {
                override fun success(value: Any?) { result = value; latch.countDown() }
                override fun error(code: String, message: String?, details: Any?) {
                    failure = ZeppCoordinationException(code, message ?: "Debug wireless non disponibile.")
                    latch.countDown()
                }
                override fun notImplemented() { failure = ZeppCoordinationException("ADB_UNAVAILABLE", "Servizio ADB non disponibile."); latch.countDown() }
            })
        }
        if (!latch.await(75, TimeUnit.SECONDS)) {
            ZeppDiagnostics.record("COORDINATOR_CALL_ERROR", "method=$method")
            throw ZeppCoordinationException("ADB_CALL_TIMEOUT", "Il servizio ADB non risponde entro il limite del coordinatore.")
        }
        failure?.let {
            ZeppDiagnostics.record("COORDINATOR_CALL_ERROR", "method=$method")
            throw it
        }
        ZeppDiagnostics.record("COORDINATOR_CALL_OK", "method=$method")
        return result
    }

    fun status(): Map<String, Any> = mapOf(
        "state" to (if (call("ready") == true) "ready" else "not_running"),
        "enabled" to preferences.getBoolean("coordination_enabled", false),
        "pendingRestore" to preferences.getBoolean("restore_pending", false),
        "diagnostics" to (call("diagnostics") ?: mapOf("leaseState" to "unknown")),
    )

    fun setEnabled(enabled: Boolean) {
        if (enabled && status()["state"] != "ready") throw IOException("Configura e collega il debug wireless dentro SyncBeat.")
        check(preferences.edit().putBoolean("coordination_enabled", enabled).commit())
    }

    fun prepare() { call("prepare") }

    fun begin(timeoutMillis: Long) {
        check(preferences.edit().putBoolean("restore_pending", true).commit())
        call("begin", timeoutMillis)
    }

    fun restore(allowBootstrap: Boolean = true) {
        if (!preferences.getBoolean("restore_pending", false)) return
        try {
            call("restore", allowBootstrap)
            check(preferences.edit().putBoolean("restore_pending", false).commit())
        } catch (error: Exception) {
            throw ZeppCoordinationException(
                (error as? ZeppCoordinationException)?.code ?: "ADB_RESTORE_FAILED",
                "Ripristino Zepp non confermato. ${error.message ?: "Usa Ripristina permessi Zepp."}"
            )
        }
    }

    fun testCycle() {
        var primary: Exception? = null
        try { begin(20_000) }
        catch (error: Exception) {
            ZeppDiagnostics.record("TEST_PRIMARY_ERROR")
            primary = error
        }
        try { restore(allowBootstrap = false) }
        catch (error: Exception) {
            ZeppDiagnostics.record("TEST_RECOVERY_ERROR")
            val initial = primary
            if (initial == null) throw error
            throw ZeppCoordinationException(
                (initial as? ZeppCoordinationException)?.code ?: "ADB_BEGIN_FAILED",
                "${initial.message}\n${error.message}"
            )
        }
        primary?.let { throw it }
    }
}
