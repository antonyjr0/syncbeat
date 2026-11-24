package com.example.syncbeat

import org.junit.Assert.*
import org.junit.Test

class WirelessDebugPreparationTest {
    private class Device : WirelessDebugPreparation.Device {
        var wifi = true
        var authorized = true
        var active = false
        var accepted = true
        var reads = 0
        var writes = 0
        override fun wifiConnected() = wifi
        override fun mayWriteSecureSettings() = authorized
        override fun enabled(): Boolean { reads++; return active }
        override fun enable(): Boolean { writes++; return accepted }
    }

    @Test fun withoutWifiDoesNotReadOrWriteProtectedSettings() {
        val device = Device().apply { wifi = false }
        assertEquals("no_wifi", WirelessDebugPreparation(device).prepare())
        assertEquals(0, device.reads)
        assertEquals(0, device.writes)
    }
    @Test fun withoutGrantNeverTouchesProtectedSettings() {
        val device = Device().apply { authorized = false }
        assertEquals("authorization_required", WirelessDebugPreparation(device).prepare())
        assertEquals(0, device.reads)
        assertEquals(0, device.writes)
    }
    @Test fun enabledServiceIsNotWrittenAgain() {
        val device = Device().apply { active = true }
        assertEquals("already_enabled", WirelessDebugPreparation(device).prepare())
        assertEquals(0, device.writes)
    }
    @Test fun wifiAndAuthorizationAllowExactlyOneActivationRequest() {
        val device = Device()
        assertEquals("enable_requested", WirelessDebugPreparation(device).prepare())
        assertEquals(1, device.writes)
    }
    @Test fun rejectedWriteFailsWithoutRetryOrReportingSuccess() {
        val device = Device().apply { accepted = false }
        try {
            WirelessDebugPreparation(device).prepare()
            fail("Rejected write must fail")
        } catch (_: IllegalStateException) { }
        assertEquals(1, device.writes)
    }
}
