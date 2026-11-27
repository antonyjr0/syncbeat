package com.example.syncbeat

import org.junit.Assert.*
import org.junit.Test

class AdbDiscoveryEntriesTest {
    @Test fun updateReplacesPortRatherThanKeepingFirstResolution() {
        val entries = AdbDiscoveryEntries()
        val ticket = entries.found("synthetic-service")!!
        entries.update(ticket, mapOf("port" to 12345))
        entries.update(ticket, mapOf("port" to 23456))
        assertEquals(listOf(mapOf("port" to 23456)), entries.snapshot())
        assertFalse(entries.pendingResolution)
    }
    @Test fun lossRemovesObsoleteRecordAndIgnoresLateCallback() {
        val entries = AdbDiscoveryEntries()
        val old = entries.found("synthetic-service")!!
        entries.update(old, mapOf("port" to 12345))
        entries.lost(old.name)
        assertFalse(entries.update(old, mapOf("port" to 12345)))
        assertTrue(entries.snapshot().isEmpty())
        val current = entries.found(old.name)!!
        assertFalse(entries.update(old, mapOf("port" to 12345)))
        entries.update(current, mapOf("port" to 23456))
        assertEquals(23456, entries.snapshot().single()["port"])
    }
    @Test fun missingInitialUpdateIsPendingAndFailureCannotBecomeEmptySuccess() {
        val entries = AdbDiscoveryEntries()
        val ticket = entries.found("synthetic-service")!!
        assertTrue(entries.pendingResolution)
        entries.fail(ticket)
        assertFalse(entries.pendingResolution)
        assertTrue(entries.resolutionFailed)
        entries.lost(ticket.name)
        assertFalse(entries.resolutionFailed)
    }
    @Test fun duplicateFoundDoesNotCreateAnotherRegistration() {
        val entries = AdbDiscoveryEntries()
        entries.found("synthetic-service")
        assertNull(entries.found("synthetic-service"))
        assertEquals(1, entries.size)
    }
    @Test fun trackedLossInvalidatesOldPortUntilFreshUpdateArrives() {
        val entries = AdbDiscoveryEntries()
        val ticket = entries.found("synthetic-service")!!
        entries.update(ticket, mapOf("port" to 12345))
        entries.invalidate(ticket)
        assertTrue(entries.snapshot().isEmpty())
        assertTrue(entries.pendingResolution)
        entries.update(ticket, mapOf("port" to 23456))
        assertFalse(entries.pendingResolution)
        assertEquals(23456, entries.snapshot().single()["port"])
    }
}
