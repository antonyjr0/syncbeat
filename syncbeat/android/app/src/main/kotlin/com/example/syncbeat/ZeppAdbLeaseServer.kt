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
        require(args.size == 1 && args[0].matches(Regex("syncbeat_zepp_[a-f0-9]{32}")))
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
            runCatching { helper.restore() }
            while (true) {
                val client = server.accept()
                try {
                    if (client.peerCredentials.uid != 2000 && client.peerCredentials.uid != 0) continue
                    client.soTimeout = 15_000
                    val input = client.inputStream.bufferedReader()
                    val output = client.outputStream.bufferedWriter()
                    while (true) {
                        val request = input.readLine() ?: break
                        val id = request.substringBefore('|')
                        if (!id.matches(Regex("[0-9]{1,10}"))) break
                        val command = request.substringAfter('|', "")
                        lastUse.set(System.nanoTime())
                        val response = try {
                            when {
                                command == "PING" -> "OK"
                                command == "RESTORE" -> { helper.restore(); if (helper.pendingRestore()) "ERR" else "OK" }
                                command.startsWith("BEGIN ") -> {
                                    helper.beginLease(Binder(), command.removePrefix("BEGIN ").toLong())
                                    "OK"
                                }
                                else -> "ERR"
                            }
                        } catch (_: Exception) { "ERR" }
                        output.write("$id|$response"); output.newLine(); output.flush()
                    }
                } catch (_: Exception) {
                    // EOF, timeout and disconnect all follow the same rollback.
                } finally {
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
