package com.example.syncbeat

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** A target remains pending until its closed output has been read back. */
interface PendingAudioTarget {
    fun output(): OutputStream
    fun input(): InputStream
    fun commit()
    fun rollback()
}

object PublicAudioTransaction {
    fun copy(source: InputStream, target: PendingAudioTarget, size: Long, hash: String, cancelled: () -> Boolean) {
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var written = 0L
            target.output().use { output ->
                source.use { input ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        check(!cancelled()) { "Salvataggio annullato" }
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                        written += count
                    }
                    output.flush()
                }
            }
            PublicAudioPolicy.verify(written, hex(digest.digest()), size, hash)
            val stored = MessageDigest.getInstance("SHA-256")
            var read = 0L
            target.input().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    check(!cancelled()) { "Salvataggio annullato" }
                    val count = input.read(buffer)
                    if (count < 0) break
                    stored.update(buffer, 0, count)
                    read += count
                }
            }
            PublicAudioPolicy.verify(read, hex(stored.digest()), size, hash)
            check(!cancelled()) { "Salvataggio annullato" }
            target.commit()
        } catch (error: Exception) {
            try { target.rollback() } catch (cleanup: Exception) { error.addSuppressed(cleanup) }
            throw error
        } finally { source.close() }
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
}
