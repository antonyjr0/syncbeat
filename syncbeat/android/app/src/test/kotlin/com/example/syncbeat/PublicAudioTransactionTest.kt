package com.example.syncbeat

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.security.MessageDigest

class PublicAudioTransactionTest {
    private val bytes = ByteArray(100000) { (it % 127).toByte() }
    private val hash get() = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private class Target(val broken: Boolean = false, val truncated: Boolean = false) : PendingAudioTarget {
        val output = ByteArrayOutputStream()
        var visible = false
        var removed = false
        var verified = false
        override fun output(): OutputStream = if (broken) object : OutputStream() {
            override fun write(value: Int) { throw IOException("Disk full") }
        } else output
        override fun input(): ByteArrayInputStream {
            assertFalse(visible)
            verified = true
            val bytes = output.toByteArray()
            return ByteArrayInputStream(if (truncated) bytes.copyOf(bytes.size - 1) else bytes)
        }
        override fun commit() { assertTrue(verified); visible = true }
        override fun rollback() { removed = true; visible = false }
    }
    @Test fun onlyVerifiedClosedOutputBecomesVisible() {
        val target = Target()
        PublicAudioTransaction.copy(bytes.inputStream(), target, bytes.size.toLong(), hash) { false }
        assertTrue(target.visible)
        assertFalse(target.removed)
        assertArrayEquals(bytes, target.output.toByteArray())
    }
    @Test fun incompleteSourceNeverPublishes() {
        val target = Target()
        try { PublicAudioTransaction.copy(bytes.copyOf(10).inputStream(), target, bytes.size.toLong(), hash) { false }; fail() }
        catch (_: IllegalArgumentException) { }
        assertFalse(target.visible); assertTrue(target.removed)
    }
    @Test fun truncatedDestinationIsRemovedBeforeCommit() {
        val target = Target(truncated = true)
        try { PublicAudioTransaction.copy(bytes.inputStream(), target, bytes.size.toLong(), hash) { false }; fail() }
        catch (_: IllegalArgumentException) { }
        assertFalse(target.visible); assertTrue(target.removed)
    }
    @Test fun writeErrorRollsBackPendingItem() {
        val target = Target(broken = true)
        try { PublicAudioTransaction.copy(bytes.inputStream(), target, bytes.size.toLong(), hash) { false }; fail() }
        catch (_: IOException) { }
        assertFalse(target.visible); assertTrue(target.removed)
    }
    @Test fun cancellationRemovesPendingItem() {
        val target = Target()
        try { PublicAudioTransaction.copy(bytes.inputStream(), target, bytes.size.toLong(), hash) { true }; fail() }
        catch (_: IllegalStateException) { }
        assertFalse(target.visible); assertTrue(target.removed)
    }
}
