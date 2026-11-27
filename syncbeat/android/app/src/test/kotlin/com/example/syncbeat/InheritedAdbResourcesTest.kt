package com.example.syncbeat

import org.junit.Assert.*
import org.junit.Test

class InheritedAdbResourcesTest {
    private class Table : InheritedAdbResources.Descriptors {
        var entries = listOf(0, 1, 2, 3, 26, 70, 71)
        val inherited = setOf(0, 1, 2, 26, 70, 71)
        val inspected = mutableListOf<Int>()
        val closed = mutableListOf<Int>()
        var failClose = false
        override fun numbers() = entries
        override fun inherited(number: Int) = number in inherited
        override fun peerPath(number: Int): String? {
            inspected.add(number)
            return when (number) {
                0, 1, 2, 3, 26 -> "/dev/socket/mdnsd"
                71 -> "/dev/socket/mdnsd-other"
                else -> null // TCP socket or non-socket descriptor.
            }
        }
        override fun close(number: Int) {
            if (failClose) error("close failed")
            closed.add(number)
        }
    }

    @Test fun closesOnlyInheritedMdnsAndPreservesBootstrapRuntimeAndOtherSockets() {
        val table = Table()
        assertEquals(1, InheritedAdbResources.closeMdns(table))
        assertEquals(listOf(26), table.closed)
        assertEquals(listOf(26, 70, 71), table.inspected)
    }

    @Test fun repeatedEnumerationCannotCloseAReusedDescriptorTwice() {
        val table = Table().apply { entries = listOf(26, 26) }
        assertEquals(1, InheritedAdbResources.closeMdns(table))
        assertEquals(listOf(26), table.closed)
    }

    @Test fun cleanupFailurePropagatesBeforeCallerCanAnnounceReady() {
        val table = Table().apply { failClose = true }
        assertThrows(IllegalStateException::class.java) { InheritedAdbResources.closeMdns(table) }
        assertTrue(table.closed.isEmpty())
    }

    @Test fun usesProcCloseOnExecBitRatherThanFcntlBit() {
        val mask = 0x80000L
        assertFalse(InheritedAdbResources.inheritedFlags("pos:\t0\nflags:\t02000002\n", mask))
        assertTrue(InheritedAdbResources.inheritedFlags("flags:\t02\n", mask))
        assertTrue(InheritedAdbResources.inheritedFlags("flags:\t00\n", mask))
        assertThrows(IllegalStateException::class.java) {
            InheritedAdbResources.inheritedFlags("flags:\tinvalid\n", mask)
        }
    }
}
