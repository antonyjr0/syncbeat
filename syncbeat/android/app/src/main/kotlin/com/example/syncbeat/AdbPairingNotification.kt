package com.example.syncbeat

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface
import java.util.UUID

@Suppress("DEPRECATION") // Discovery and resolution support Android 11 and 12.
internal class AdbPairingNotification(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val nsd = activity.getSystemService(NsdManager::class.java)
    private val notifications = activity.getSystemService(NotificationManager::class.java)
    private var result: MethodChannel.Result? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var receiver: BroadcastReceiver? = null
    private var replyIntent: PendingIntent? = null
    private val timeout = Runnable { fail("Tempo scaduto. Genera un nuovo codice di abbinamento.") }
    private val services = mutableMapOf<String, Int>()
    private val pendingServices = ArrayDeque<NsdServiceInfo>()
    private val visibleServices = mutableSetOf<String>()
    private var resolving = false

    fun start(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 30 || this.result != null) {
            result.error("PAIRING", "Abbinamento via notifica non disponibile ora.", null)
            return
        }
        this.result = result
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
        } else {
            discover()
        }
    }

    fun onPermissionResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        if (result != null) {
            if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) discover()
            else fail("Consenti le notifiche di SyncBeat per inserire il codice dalle Impostazioni.")
        }
        return true
    }

    private fun discover() {
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL, "Abbinamento debug wireless", NotificationManager.IMPORTANCE_DEFAULT)
        )
        if (!notifications.areNotificationsEnabled() ||
            notifications.getNotificationChannel(CHANNEL).importance == NotificationManager.IMPORTANCE_NONE
        ) {
            fail("Attiva le notifiche di abbinamento nelle impostazioni di SyncBeat.")
            return
        }
        val action = "${activity.packageName}.ADB_PAIRING.${UUID.randomUUID()}"
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStopDiscoveryFailed(type: String, error: Int) = Unit
            override fun onStartDiscoveryFailed(type: String, error: Int) {
                handler.post {
                    if (discovery === this) fail("Ricerca della porta di abbinamento non riuscita.")
                }
            }

            override fun onServiceFound(info: NsdServiceInfo) {
                handler.post {
                    if (discovery === this && visibleServices.add(info.serviceName)) {
                        pendingServices.addLast(info)
                        resolveNext(this)
                    }
                }
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                handler.post {
                    if (discovery !== this) return@post
                    visibleServices.remove(info.serviceName)
                    pendingServices.removeAll { it.serviceName == info.serviceName }
                    services.remove(info.serviceName)
                    updateNotification()
                }
            }
        }
        val replyReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != action || receiver !== this) return
                val port = services.values.singleOrNull() ?: return
                val code = RemoteInput.getResultsFromIntent(intent)
                    ?.getCharSequence(CODE)?.toString()?.trim()
                if (code == null || !code.matches(Regex("[0-9]{6}"))) {
                    updateNotification("Inserisci le sei cifre mostrate da Android.")
                    return
                }
                val callback = result
                close()
                callback?.success(mapOf("port" to port, "code" to code))
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                activity.registerReceiver(replyReceiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(replyReceiver, IntentFilter(action))
            }
            receiver = replyReceiver
            replyIntent = PendingIntent.getBroadcast(
                activity, 0, Intent(action).setPackage(activity.packageName), PendingIntent.FLAG_MUTABLE
            )
            discovery = listener
            nsd.discoverServices("_adb-tls-pairing._tcp.", NsdManager.PROTOCOL_DNS_SD, listener)
            handler.postDelayed(timeout, 180_000)
            openWirelessDebuggingSettings(activity)
        } catch (_: Exception) {
            fail("Impossibile avviare l’abbinamento via notifica.")
        }
    }

    private fun resolveNext(owner: NsdManager.DiscoveryListener) {
        if (resolving || pendingServices.isEmpty()) return
        val info = pendingServices.removeFirst()
        resolving = true
        val resolver = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, error: Int) = complete(info, false)
            override fun onServiceResolved(info: NsdServiceInfo) = complete(info, true)

            private fun complete(resolved: NsdServiceInfo, success: Boolean) {
                handler.post {
                    if (discovery !== owner) return@post
                    resolving = false
                    if (success && info.serviceName in visibleServices &&
                        resolved.port in 1..65535 && isLocal(resolved)
                    ) {
                        services[info.serviceName] = resolved.port
                        updateNotification()
                    }
                    resolveNext(owner)
                }
            }
        }
        try {
            nsd.resolveService(info, resolver)
        } catch (_: RuntimeException) {
            fail("Impossibile rilevare la porta di abbinamento.")
        }
    }

    private fun isLocal(info: NsdServiceInfo): Boolean {
        val hosts = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
        return hosts.any { host ->
            host.isLoopbackAddress || runCatching { NetworkInterface.getByInetAddress(host) != null }.getOrDefault(false)
        }
    }

    private fun updateNotification(message: String = "Inserisci il codice mostrato da Debug wireless.") {
        val intent = replyIntent ?: return
        if (services.size != 1) {
            notifications.cancel(NOTIFICATION_ID)
            return
        }
        val input = RemoteInput.Builder(CODE).setLabel("Codice di 6 cifre").build()
        val action = Notification.Action.Builder(null, "Inserisci codice", intent)
            .addRemoteInput(input)
            .setAllowGeneratedReplies(false)
            .build()
        notifications.notify(
            NOTIFICATION_ID,
            Notification.Builder(activity, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Abbina SyncBeat")
                .setContentText(message)
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setOnlyAlertOnce(true)
                .addAction(action)
                .build()
        )
    }

    fun cancel() {
        if (result != null) fail("Abbinamento annullato.")
    }

    private fun fail(message: String) {
        val callback = result
        close()
        callback?.error("PAIRING", message, null)
    }

    private fun close() {
        result = null
        handler.removeCallbacks(timeout)
        discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discovery = null
        receiver?.let(activity::unregisterReceiver)
        receiver = null
        replyIntent?.cancel()
        replyIntent = null
        services.clear()
        pendingServices.clear()
        visibleServices.clear()
        resolving = false
        notifications.cancel(NOTIFICATION_ID)
    }

    private companion object {
        const val CHANNEL = "adb_pairing"
        const val CODE = "code"
        const val NOTIFICATION_ID = 4170
        const val PERMISSION_REQUEST = 4171
    }
}

internal fun openWirelessDebuggingSettings(activity: Activity) {
    // Settings opens the wireless debugging page for its Quick Settings tile shortcut.
    val settingsPackage = "com.android.settings"
    val wirelessPage = Intent("android.service.quicksettings.action.QS_TILE_PREFERENCES")
        .setClassName(settingsPackage, "$settingsPackage.Settings\$DevelopmentSettingsActivity")
        .putExtra(
            Intent.EXTRA_COMPONENT_NAME,
            ComponentName(settingsPackage, "$settingsPackage.development.qstile.DevelopmentTiles\$WirelessDebugging")
        )
    try {
        activity.startActivity(wirelessPage)
    } catch (_: ActivityNotFoundException) {
        activity.startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
    } catch (_: SecurityException) {
        activity.startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
    }
}
