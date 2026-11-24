package com.example.syncbeat

/** Only the fixed wireless-debug setting, gated before any protected read/write. */
internal class WirelessDebugPreparation(private val device: Device) {
    interface Device {
        fun wifiConnected(): Boolean
        fun mayWriteSecureSettings(): Boolean
        fun enabled(): Boolean
        fun enable(): Boolean
    }

    fun prepare(): String {
        if (!device.wifiConnected()) return "no_wifi"
        if (!device.mayWriteSecureSettings()) return "authorization_required"
        if (device.enabled()) return "already_enabled"
        check(device.enable()) { "Wireless debug activation not accepted" }
        // A setting write is a request, not proof that adbd is listening.
        // Dart still requires a unique NSD candidate and authenticated TLS.
        return "enable_requested"
    }
}
