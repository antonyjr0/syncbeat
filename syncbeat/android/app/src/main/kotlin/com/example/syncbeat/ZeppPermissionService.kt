package com.example.syncbeat

import android.os.IBinder
import android.os.Process
import android.util.AtomicFile
import com.example.syncbeat.zepp.ZeppPermissionLease
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Runs only in the authorized ADB shell process. No arbitrary package/command IPC. */
class ZeppPermissionService : IZeppPermissionService.Stub() {
    private val packageName = "com.huami.watch.hmwatchmanager"
    private val timers = Executors.newSingleThreadScheduledExecutor()
    private val directory = File("/data/local/tmp/syncbeat-zepp-permissions-v1")
    private val record = AtomicFile(File(directory, "restore"))
    private var owner: IBinder? = null
    private var ownerDeath: IBinder.DeathRecipient? = null
    private var watchdog: ScheduledFuture<*>? = null
    private var retry: ScheduledFuture<*>? = null
    private var generation = 0L
    private var lockFile: java.io.RandomAccessFile? = null
    private var processLock: java.nio.channels.FileLock? = null

    private fun acquireProcessLock(): Boolean {
        if (processLock?.isValid == true) return true
        if (!directory.exists() && !directory.mkdir()) throw IOException("Archivio ripristino non disponibile.")
        val file = java.io.RandomAccessFile(File(directory, "lease.lock"), "rw")
        val lock = try { file.channel.tryLock() }
            catch (_: java.nio.channels.OverlappingFileLockException) { null }
        if (lock == null) { file.close(); return false }
        lockFile = file; processLock = lock
        return true
    }

    private fun releaseProcessLock() {
        runCatching { processLock?.release() }; processLock = null
        runCatching { lockFile?.close() }; lockFile = null
    }

    private fun command(vararg arguments: String): String {
        check(Process.myUid() == 2000 || Process.myUid() == 0) { "Il servizio deve essere avviato da ADB." }
        if (!directory.exists() && !directory.mkdir()) throw IOException("Archivio ripristino non disponibile.")
        directory.setReadable(false, false); directory.setReadable(true, true)
        directory.setWritable(false, false); directory.setWritable(true, true)
        directory.setExecutable(false, false); directory.setExecutable(true, true)
        val output = File.createTempFile("command-", ".txt", directory)
        try {
            val process = ProcessBuilder(*arguments).redirectErrorStream(true).redirectOutput(output).start()
            if (!process.waitFor(10, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                throw IOException("Il comando di gestione permessi non risponde.")
            }
            val text = output.readText()
            if (process.exitValue() != 0 || text.contains("SecurityException")) {
                throw IOException("ADB non può modificare i permessi. Controlla Debug USB (Impostazioni di sicurezza).")
            }
            return text
        } finally { output.delete() }
    }

    private val lease = ZeppPermissionLease(object : ZeppPermissionLease.Permissions {
        override fun granted(name: String): Boolean {
            val dump = command("/system/bin/dumpsys", "package", packageName)
            // Support only the primary Android user, never another work/profile user.
            val start = Regex("(?m)^\\s*User 0:").find(dump)?.range?.first
                ?: throw IOException("Zepp non è disponibile nel profilo principale.")
            val tail = dump.substring(start)
            val next = Regex("(?m)^\\s*User [1-9][0-9]*:").find(tail)?.range?.first ?: tail.length
            val section = tail.take(next)
            return section.contains("$name: granted=true")
        }

        override fun setGranted(name: String, value: Boolean) {
            require(ZeppPermissionLease.PERMISSIONS.contains(name))
            command("/system/bin/pm", if (value) "grant" else "revoke", "--user", "0", packageName, name)
        }
    }, object : ZeppPermissionLease.Journal {
        override fun read(): Map<String, Boolean>? {
            if (directory.exists() && (!directory.canRead() || !directory.canExecute())) {
                throw IOException("Registro ripristino Zepp non accessibile.")
            }
            val text = try { record.openRead().use { it.readBytes().toString(Charsets.UTF_8) } }
                catch (error: FileNotFoundException) {
                    if (record.baseFile.exists() || File(directory, "restore.bak").exists()) {
                        throw IOException("Registro ripristino Zepp non leggibile.", error)
                    }
                    return null
                }
            if (text.length != 3 || text.any { it != '1' && it != '0' }) throw IOException("Registro ripristino Zepp non valido.")
            return ZeppPermissionLease.PERMISSIONS.mapIndexed { index, name -> name to (text[index] == '1') }.toMap()
        }

        override fun save(snapshot: Map<String, Boolean>) {
            if (!directory.exists() && !directory.mkdir()) throw IOException("Impossibile salvare lo stato dei permessi.")
            val stream = record.startWrite()
            try {
                stream.write(ZeppPermissionLease.PERMISSIONS.map { if (snapshot[it] == true) '1' else '0' }.joinToString("").toByteArray())
                record.finishWrite(stream)
            } catch (error: Exception) { record.failWrite(stream); throw IOException("Impossibile salvare il ripristino.", error) }
        }

        override fun clear() {
            record.delete()
            if (record.baseFile.exists() || File(directory, "restore.bak").exists()) {
                throw IOException("Impossibile concludere il registro ripristino.")
            }
        }
    })

    @Synchronized
    override fun beginLease(token: IBinder, timeoutMillis: Long) {
        check(owner == null) { "Un trasferimento coordinato è già in corso." }
        require(timeoutMillis in 10_000..900_000) { "Durata sospensione non valida." }
        check(token.isBinderAlive) { "SyncBeat non è più collegata." }
        check(acquireProcessLock()) { "Un altro servizio sta gestendo i permessi di Zepp." }
        val expectedGeneration = ++generation
        val death = IBinder.DeathRecipient { timers.execute { restoreSafely(expectedGeneration) } }
        token.linkToDeath(death, 0)
        owner = token
        ownerDeath = death
        try {
            lease.begin()
            if (!token.isBinderAlive) throw IOException("SyncBeat si è chiusa durante la preparazione.")
            watchdog = timers.schedule({ restoreSafely(expectedGeneration) }, timeoutMillis, TimeUnit.MILLISECONDS)
        } catch (error: Exception) {
            restoreSafely(expectedGeneration)
            throw IllegalStateException("Sospensione Zepp non riuscita. Controlla il ripristino dei permessi.", error)
        }
    }

    @Synchronized
    override fun restore() {
        // An idle/old helper must never undo another process's active lease.
        if (!acquireProcessLock()) return
        watchdog?.cancel(false); watchdog = null
        ownerDeath?.let { death -> runCatching { owner?.unlinkToDeath(death, 0) } }
        owner = null; ownerDeath = null
        try {
            lease.restore()
            releaseProcessLock()
            generation++
            retry?.cancel(false); retry = null
        } catch (error: Exception) {
            // Also retry failures of an explicit restore/finally call, after the
            // watchdog and client death registration have already been cleared.
            val expectedGeneration = generation
            retry?.cancel(false)
            retry = timers.schedule({
                synchronized(this) { retry = null; restoreSafely(expectedGeneration) }
            }, 10, TimeUnit.SECONDS)
            throw IllegalStateException("Ripristino Zepp non confermato. Usa Ripristina permessi Zepp.", error)
        }
    }

    @Synchronized
    private fun restoreSafely(expectedGeneration: Long = generation) {
        if (expectedGeneration != generation) return
        try { restore() }
        catch (_: Exception) { /* restore() keeps the record and schedules recovery. */ }
    }

    @Synchronized
    override fun pendingRestore(): Boolean = try { lease.pending() }
        catch (error: Exception) { throw IllegalStateException("Stato ripristino Zepp non leggibile.", error) }

    override fun destroy() {
        // A failed restore must retain the helper and undo record for recovery.
        try { restore(); timers.shutdown(); kotlin.system.exitProcess(0) }
        catch (_: Exception) { restoreSafely() }
    }
}
