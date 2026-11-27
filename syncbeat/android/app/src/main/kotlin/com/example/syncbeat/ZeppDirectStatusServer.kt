package com.example.syncbeat

import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.charset.StandardCharsets.US_ASCII
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.TimeUnit

internal class ZeppDirectStatusServer(
    secret: ByteArray,
    private val uid: Int,
    private val pid: Int,
    private val leaseCommand: (String) -> String = { "ERR" },
) : Closeable {
    init {
        require(secret.size == 32 && (uid == 2000 || uid == 0) && pid > 0)
    }

    // TCP has no SO_PEERCRED. Access is established by the bootstrap-only,
    // 256-bit credential. After authentication the listening socket closes,
    // binding the session to that one connection until the app disconnects.
    private val credential = Base64.getEncoder().encode(secret)
    private val listener = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
    val port: Int = listener.localPort
    @Volatile private var client: Socket? = null
    @Volatile private var closed = false

    fun serve() {
        val authenticationDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
        try {
            while (!closed && !listener.isClosed) {
                try {
                    listener.soTimeout = remainingMillis(authenticationDeadline)
                    listener.accept().use { connection ->
                        client = connection
                        if (!connection.inetAddress.isLoopbackAddress) return@use
                        val frame = readLine(connection, authenticationDeadline) ?: return@use
                        val id = requestId(frame) ?: return@use
                        val command = frame.substringAfter('|')
                        val supplied = command.removePrefix("AUTH ").toByteArray(US_ASCII)
                        val authorized = command.startsWith("AUTH ") && MessageDigest.isEqual(credential, supplied)
                        supplied.fill(0)
                        if (!authorized) {
                            reply(connection, id, "ERR")
                            return@use
                        }
                        credential.fill(0)
                        listener.close()
                        reply(connection, id, "OK")
                        while (!closed) {
                            val request = readLine(connection, null) ?: return
                            val requestId = requestId(request) ?: return
                            val command = request.substringAfter('|')
                            val response = when {
                                command == "STATUS" -> "STATUS:1:$uid:$pid"
                                command == "PING" -> "OK"
                                command == "RESTORE" || command.matches(Regex("BEGIN [0-9]{5,6}")) -> leaseCommand(command)
                                else -> "ERR"
                            }
                            reply(connection, requestId, response)
                        }
                        return
                    }
                } catch (_: IOException) {
                    if (listener.isClosed || System.nanoTime() >= authenticationDeadline) return
                } finally {
                    client = null
                }
            }
        } finally {
            close()
        }
    }

    private fun requestId(frame: String): String? {
        if (!frame.contains('|')) return null
        return frame.substringBefore('|').takeIf { it.matches(Regex("[0-9]{1,10}")) }
    }

    private fun reply(connection: Socket, id: String, response: String) {
        connection.getOutputStream().apply {
            write("$id|$response\n".toByteArray(US_ASCII))
            flush()
        }
    }

    private fun readLine(connection: Socket, authenticationDeadline: Long?): String? {
        // An authenticated connection may remain idle without Wi-Fi. Once a
        // frame starts, bound its size and total read time, including trickles.
        connection.soTimeout = authenticationDeadline?.let { remainingMillis(it) } ?: 0
        val input = connection.getInputStream()
        var value = input.read()
        if (value == -1) return null
        val deadline = authenticationDeadline ?: (System.nanoTime() + TimeUnit.SECONDS.toNanos(5))
        val bytes = ByteArrayOutputStream()
        while (value != -1) {
            if (value == 10) return bytes.toString("US-ASCII").removeSuffix("\r")
            if (bytes.size() >= 128 || (value !in 32..126 && value != 13)) throw IOException("Invalid frame")
            bytes.write(value)
            connection.soTimeout = remainingMillis(deadline)
            value = input.read()
        }
        throw EOFException("Incomplete frame")
    }

    private fun remainingMillis(deadline: Long): Int {
        val remaining = deadline - System.nanoTime()
        if (remaining <= 0) throw SocketTimeoutException("Deadline exceeded")
        return (TimeUnit.NANOSECONDS.toMillis(remaining) + 1).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    override fun close() {
        closed = true
        credential.fill(0)
        runCatching { listener.close() }
        runCatching { client?.close() }
    }

    companion object {
        fun readBootstrapSecret(input: InputStream): ByteArray {
            val encoded = ByteArrayOutputStream()
            var value = input.read()
            while (value != 10) {
                if (value == -1 || encoded.size() >= 44 || value !in 33..126) throw IOException("Invalid bootstrap credential")
                encoded.write(value)
                value = input.read()
            }
            val secret = try { Base64.getDecoder().decode(encoded.toByteArray()) }
                catch (_: IllegalArgumentException) { throw IOException("Invalid bootstrap credential") }
            if (encoded.size() != 44 || secret.size != 32) {
                secret.fill(0)
                throw IOException("Invalid bootstrap credential")
            }
            return secret
        }
    }
}
