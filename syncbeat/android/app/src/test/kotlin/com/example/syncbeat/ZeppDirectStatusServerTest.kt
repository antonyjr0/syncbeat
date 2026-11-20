package com.example.syncbeat

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.Base64
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ZeppDirectStatusServerTest {
    private val secret = ByteArray(32) { (it + 1).toByte() }
    private val credential = Base64.getEncoder().encodeToString(secret)

    private fun connect(port: Int) = Socket().apply {
        connect(InetSocketAddress("127.0.0.1", port), 1000)
        soTimeout = 2000
    }

    private fun send(socket: Socket, frame: String) {
        socket.getOutputStream().apply {
            write((frame + "\n").toByteArray(Charsets.US_ASCII))
            flush()
        }
    }

    @Test fun authenticationIsRequiredAndOnlyStatusIsAccepted() {
        val server = ZeppDirectStatusServer(secret, 2000, 1234)
        val executor = Executors.newSingleThreadExecutor()
        val running = executor.submit { server.serve() }
        try {
            connect(server.port).use { socket ->
                send(socket, "1|STATUS")
                assertEquals("1|ERR", socket.getInputStream().bufferedReader().readLine())
            }
            connect(server.port).use { socket ->
                send(socket, "2|AUTH invalid")
                assertEquals("2|ERR", socket.getInputStream().bufferedReader().readLine())
            }
            connect(server.port).use { socket ->
                val replies = socket.getInputStream().bufferedReader()
                send(socket, "3|AUTH $credential")
                assertEquals("3|OK", replies.readLine())
                send(socket, "4|STATUS")
                assertEquals("4|STATUS:1:2000:1234", replies.readLine())
                for (command in listOf("BEGIN 20000", "RESTORE", "PING", "AUTH $credential")) {
                    send(socket, "5|$command")
                    assertEquals("5|ERR", replies.readLine())
                }
                send(socket, "6|STATUS")
                assertEquals("6|STATUS:1:2000:1234", replies.readLine())
                try {
                    connect(server.port).close()
                    fail("The listener must close after authentication")
                } catch (_: IOException) { }
            }
            // EOF is the session boundary. No privileged process remains idle
            // after the owner connection disappears in this status-only mode.
            running.get(2, TimeUnit.SECONDS)
        } finally {
            server.close()
            executor.shutdownNow()
        }
    }

    @Test fun newHelperRejectsPreviousSessionCredential() {
        val server = ZeppDirectStatusServer(ByteArray(32) { 99 }, 2000, 1235)
        val executor = Executors.newSingleThreadExecutor()
        val running = executor.submit { server.serve() }
        try {
            connect(server.port).use { socket ->
                send(socket, "1|AUTH $credential")
                assertEquals("1|ERR", socket.getInputStream().bufferedReader().readLine())
            }
            server.close()
            running.get(2, TimeUnit.SECONDS)
        } finally {
            server.close()
            executor.shutdownNow()
        }
    }

    @Test fun oversizedUnauthenticatedFrameIsClosed() {
        val server = ZeppDirectStatusServer(secret, 2000, 1234)
        val executor = Executors.newSingleThreadExecutor()
        executor.submit { server.serve() }
        try {
            connect(server.port).use { socket ->
                send(socket, "1|AUTH " + "x".repeat(129))
                try {
                    assertNull(socket.getInputStream().bufferedReader().readLine())
                } catch (_: IOException) { /* Reset is also a closed frame. */ }
            }
        } finally {
            server.close()
            executor.shutdownNow()
        }
    }

    @Test fun stdinCredentialIsBoundedAndMustHaveExpectedLength() {
        val decoded = ZeppDirectStatusServer.readBootstrapSecret(
            ByteArrayInputStream((credential + "\n").toByteArray(Charsets.US_ASCII))
        )
        assertTrue(secret.contentEquals(decoded))
        for (invalid in listOf("", credential, "x".repeat(1000), "invalid\n")) {
            try {
                ZeppDirectStatusServer.readBootstrapSecret(ByteArrayInputStream(invalid.toByteArray()))
                fail("Invalid bootstrap input accepted")
            } catch (_: IOException) { }
        }
    }
}
