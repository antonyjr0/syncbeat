package com.example.syncbeat

import android.net.LocalServerSocket
import android.os.Binder
import android.os.Process
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Shell-only, local ADB endpoint. No arbitrary command/package interface. */
object ZeppAdbLeaseServer {
    @JvmStatic fun main(args: Array<String>) {
        check(Process.myUid() == 2000 || Process.myUid() == 0)
        if (args.contentEquals(arrayOf("--direct-status-v1"))) {
            // The launching shell disables echo before this marker. Only then
            // may Dart send the credential on stdin, never on the command line.
            System.out.println("SYNCBEAT_DIRECT_INPUT_V1")
            System.out.flush()
            val secret = ZeppDirectStatusServer.readBootstrapSecret(System.`in`)
            val statusServer = try { ZeppDirectStatusServer(secret, Process.myUid(), Process.myPid()) }
                finally { secret.fill(0) }
            statusServer.use {
                System.out.println("SYNCBEAT_DIRECT_READY_V1:${it.port}")
                System.out.flush()
                System.`in`.close()
                System.out.close()
                it.serve()
            }
            return
        }
        require(args.size == 1 && args[0].matches(Regex("syncbeat_zepp_[a-f0-9]{32}")))
        ZeppDiagnostics.record("SERVER_START")
        val helper = ZeppPermissionService()
        val server = LocalServerSocket(args[0])
        val idle = Executors.newSingleThreadScheduledExecutor()
        // No live transaction survives losing its client. The helper also has
        // its independent watchdog, durable undo record and recovery retries.
        val lastUse = java.util.concurrent.atomic.AtomicLong(System.nanoTime())
        idle.scheduleAtFixedRate({
            if (System.nanoTime() - lastUse.get() > TimeUnit.MINUTES.toNanos(15)) runCatching { server.close() }
        }, 1, 1, TimeUnit.MINUTES)
        try {
            try {
                helper.restore()
                check(!helper.pendingRestore())
            } catch (_: Exception) {
                System.out.println("SYNCBEAT_RECOVERY_PENDING_V1")
                System.out.flush()
                System.out.close()
                return
            }
            ZeppDiagnostics.record("SERVER_READY")
            System.out.println("SYNCBEAT_READY_V1")
            System.out.flush()
            // Release only the startup pipe. The detached service keeps its socket,
            // watchdog and durable recovery independently of the shell stream.
            System.out.close()
            while (true) {
                val client = server.accept()
                try {
                    if (client.peerCredentials.uid != 2000 && client.peerCredentials.uid != 0) continue
                    client.soTimeout = 15_000
                    val input = client.inputStream.bufferedReader()
                    val output = client.outputStream.bufferedWriter()
                    while (true) {
                        val request = input.readLine()
                        if (request == null) {
                            ZeppDiagnostics.record("SERVER_CLIENT_EOF")
                            break
                        }
                        val id = request.substringBefore('|')
                        if (!id.matches(Regex("[0-9]{1,10}"))) break
                        val command = request.substringAfter('|', "")
                        if (command != "STATUS") lastUse.set(System.nanoTime())
                        val code = when {
                            command == "STATUS" -> "STATUS"
                            command == "RESTORE" -> "RESTORE"
                            command == "PING" -> "PING"
                            command.startsWith("BEGIN ") -> "BEGIN"
                            else -> "INVALID"
                        }
                        ZeppDiagnostics.record("SERVER_${code}_ENTER", "request=$id")
                        val response = try {
                            when {
                                command == "STATUS" -> helper.diagnosticStatus()
                                command == "PING" -> "OK"
                                command == "RESTORE" -> { helper.restore(); if (helper.pendingRestore()) "ERR" else "OK" }
                                command.startsWith("BEGIN ") -> {
                                    helper.beginLease(Binder(), command.removePrefix("BEGIN ").toLong())
                                    "OK"
                                }
                                else -> "ERR"
                            }
                        } catch (_: Exception) { "ERR" }
                        ZeppDiagnostics.record("SERVER_${code}_REPLY", "request=$id ok=${response != "ERR"}")
                        output.write("$id|$response"); output.newLine(); output.flush()
                    }
                } catch (_: java.net.SocketTimeoutException) {
                    ZeppDiagnostics.record("SERVER_CLIENT_TIMEOUT")
                } catch (_: Exception) {
                    ZeppDiagnostics.record("SERVER_CLIENT_ERROR")
                    // EOF, timeout and disconnect all follow the same rollback.
                } finally {
                    ZeppDiagnostics.record("SERVER_CLIENT_FINALLY")
                    runCatching { helper.restore() }
                    runCatching { client.close() }
                }
            }
        } finally {
            idle.shutdownNow()
            runCatching { server.close() }
            helper.destroy()
        }
    }
}
