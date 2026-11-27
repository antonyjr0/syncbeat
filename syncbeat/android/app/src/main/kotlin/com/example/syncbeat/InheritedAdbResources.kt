package com.example.syncbeat

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileNotFoundException

/** Child-process startup only, before creating the helper's own sockets. */
internal object InheritedAdbResources {
    interface Descriptors {
        fun numbers(): List<Int>
        fun inherited(number: Int): Boolean
        fun peerPath(number: Int): String?
        fun close(number: Int)
    }

    fun closeMdns(descriptors: Descriptors): Int {
        var closed = 0
        for (number in descriptors.numbers().distinct()) {
            // Keep the bootstrap protocol and every runtime-owned CLOEXEC fd.
            if (number <= 2 || !descriptors.inherited(number)) continue
            if (descriptors.peerPath(number) != "/dev/socket/mdnsd") continue
            // Only this child's inherited copy. Never shutdown the shared
            // socket: adbd still owns its copy and the live registration.
            descriptors.close(number)
            closed++
        }
        return closed
    }

    fun closeMdnsAtStartup(): Int = closeMdns(AndroidDescriptors())

    internal fun inheritedFlags(info: String, closeOnExecMask: Long): Boolean {
        val value = info.lineSequence().firstOrNull { it.startsWith("flags:") }
            ?.substringAfter(':')?.trim()?.toLongOrNull(8)
            ?: error("Descriptor flags unavailable")
        // /proc fdinfo uses O_CLOEXEC, not fcntl's FD_CLOEXEC value.
        return value and closeOnExecMask == 0L
    }

    private class AndroidDescriptors : Descriptors {
        override fun numbers(): List<Int> =
            checkNotNull(File("/proc/self/fd").list()).mapNotNull(String::toIntOrNull)

        override fun inherited(number: Int): Boolean = try {
            inheritedFlags(File("/proc/self/fdinfo/$number").readText(), OsConstants.O_CLOEXEC.toLong())
        } catch (_: FileNotFoundException) {
            // The directory enumeration can include its already-closed fd.
            false
        }

        override fun peerPath(number: Int): String? {
            // fromFd duplicates; adoptFd here would steal ART's ownership and
            // can abort under fdsan. Inspect a temporary copy, then close it.
            return ParcelFileDescriptor.fromFd(number).use { copy ->
                val peer = try { Os.getpeername(copy.fileDescriptor) }
                    catch (_: android.system.ErrnoException) { return@use null }
                if (peer.javaClass.name != "android.system.UnixSocketAddress") return@use null
                // UnixSocketAddress is a framework type outside the SDK.
                // This fixed read-only accessor is used only in app_process,
                // as shell, like the existing permission helper's system APIs.
                val path = peer.javaClass.getMethod("getSunPath").invoke(peer) as ByteArray
                String(path, Charsets.UTF_8).trimEnd('\u0000')
            }
        }

        override fun close(number: Int) {
            // The exact mDNS peer and missing CLOEXEC identify adbd's unowned,
            // inherited descriptor, not a Java/runtime-owned descriptor.
            ParcelFileDescriptor.adoptFd(number).close()
        }
    }
}
