package com.example.syncbeat

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Dart owns the flutter_adb connection; native finally still owns rollback. */
internal class ZeppAdbCoordinator(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val preferences = activity.getSharedPreferences("zepp_bridge", 0)
    var onHelperLost: (() -> Unit)? = null

    private fun call(method: String, value: Any? = null): Any? {
        val latch = CountDownLatch(1)
        var result: Any? = null
        var failed = false
        main.post {
            channel.invokeMethod(method, value, object : MethodChannel.Result {
                override fun success(value: Any?) { result = value; latch.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failed = true; latch.countDown() }
                override fun notImplemented() { failed = true; latch.countDown() }
            })
        }
        if (!latch.await(75, TimeUnit.SECONDS) || failed) throw IOException("Debug wireless non disponibile. Riconnetti ADB in SyncBeat.")
        return result
    }

    fun status(): Map<String, Any> = mapOf(
        "state" to (if (call("ready") == true) "ready" else "not_running"),
        "enabled" to preferences.getBoolean("coordination_enabled", false),
        "pendingRestore" to preferences.getBoolean("restore_pending", false),
    )

    fun setEnabled(enabled: Boolean) {
        if (enabled && status()["state"] != "ready") throw IOException("Configura e collega il debug wireless dentro SyncBeat.")
        check(preferences.edit().putBoolean("coordination_enabled", enabled).commit())
    }

    fun begin(timeoutMillis: Long) {
        check(preferences.edit().putBoolean("restore_pending", true).commit())
        call("begin", timeoutMillis)
    }

    fun restore() {
        if (!preferences.getBoolean("restore_pending", false)) return
        try {
            call("restore")
            check(preferences.edit().putBoolean("restore_pending", false).commit())
        } catch (error: Exception) {
            throw IOException("Ripristino Zepp non confermato. Riconnetti il debug wireless e premi Ripristina permessi Zepp.", error)
        }
    }

    fun testCycle() { try { begin(20_000) } finally { restore() } }
}
