package com.example.syncbeat

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

internal class YoutubeJob(val id: String, val arguments: List<String>, val timeoutMs: Long, val result: MethodChannel.Result) {
    val cancelled = AtomicBoolean(false)
    val timedOut = AtomicBoolean(false)
    val started = AtomicBoolean(false)
}

internal object YoutubeJobs {
    val jobs = ConcurrentHashMap<String, YoutubeJob>()
    val main = Handler(Looper.getMainLooper())
    val worker = Executors.newSingleThreadExecutor()
    val timers = Executors.newSingleThreadScheduledExecutor()
    @Volatile var events: EventChannel.EventSink? = null
    fun cancel(id: String) {
        jobs[id]?.cancelled?.set(true)
        // Retry handles cancellation during library initialization/process launch.
        timers.execute { runCatching { YoutubeDL.destroyProcessById(id) } }
    }
}

class YoutubeOperationService : Service() {
    companion object { private const val CHANNEL = "youtube_operations"; private const val NOTIFICATION = 4102 }
    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "cancel") {
            intent.getStringExtra("id")?.let { YoutubeJobs.cancel(it) }
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra("id")
        val job = YoutubeJobs.jobs[id]
        if (job == null) { stopSelf(startId); return START_NOT_STICKY }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Operazioni YouTube", NotificationManager.IMPORTANCE_LOW))
            val cancel = PendingIntent.getService(this, 0, Intent(this, YoutubeOperationService::class.java).setAction("cancel").putExtra("id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("SyncBeat")
                .setContentText("Ricerca / download e conversione in corso").setOngoing(true).setContentIntent(open)
                .addAction(Notification.Action.Builder(null, "Annulla", cancel).build()).build()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else startForeground(NOTIFICATION, notification)
        } catch (error: Exception) {
            YoutubeJobs.jobs.remove(job.id)
            job.result.error("SERVICE", "Impossibile avviare il servizio: ${error.message}", null)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (job.started.compareAndSet(false, true)) YoutubeJobs.worker.execute { execute(job, startId) }
        return START_NOT_STICKY
    }

    private fun execute(job: YoutubeJob, startId: Int) {
        android.util.Log.i("SyncBeatYoutube", "Service operation started")
        val lock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "syncbeat:youtube")
        val deadline = YoutubeJobs.timers.schedule({ job.timedOut.set(true); YoutubeJobs.cancel(job.id) }, job.timeoutMs, TimeUnit.MILLISECONDS)
        val cancellation = YoutubeJobs.timers.scheduleAtFixedRate({
            if (job.cancelled.get()) runCatching { YoutubeDL.destroyProcessById(job.id) }
        }, 250, 250, TimeUnit.MILLISECONDS)
        var deliver: (() -> Unit)? = null
        try {
            lock.acquire(job.timeoutMs + 10000)
            checkActive(job)
            YoutubeDL.init(applicationContext)
            val isSearch = job.arguments.contains("--dump-json")
            if (!isSearch && job.arguments != listOf("--syncbeat-update-engine")) FFmpeg.init(applicationContext)
            checkActive(job)
            if (job.arguments == listOf("--syncbeat-update-engine")) {
                YoutubeDL.updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.STABLE)
                checkActive(job)
                deliver = { job.result.success(mapOf("output" to "")) }
                return
            }
            val split = job.arguments.indexOf("--")
            val request = YoutubeDLRequest(job.arguments.drop(split + 1))
            request.addCommands(job.arguments.take(split))
            if (job.arguments.contains("--dump-json")) request.addOption("--dump-json")
            if (job.arguments.contains("--ignore-errors")) request.addOption("--ignore-errors")
            request.addOption("--ignore-config").addOption("--no-cache-dir").addOption("--no-playlist")
                .addOption("--socket-timeout", if (isSearch) "8" else "20")
                .addOption("--retries", if (isSearch) "1" else "2")
            if (isSearch) request.addOption("--extractor-retries", "1")
            val response = YoutubeDL.execute(request, job.id, false) { _, _, line ->
                if (line.startsWith("SYNCBEAT:")) YoutubeJobs.main.post { YoutubeJobs.events?.success(mapOf("id" to job.id, "line" to line)) }
            }
            android.util.Log.i("SyncBeatYoutube", "yt-dlp completed")
            checkActive(job)
            val output = if (job.arguments.contains("--dump-json")) compactMetadata(response.out) else ""
            deliver = { job.result.success(mapOf("output" to output)) }
        } catch (error: Exception) {
            android.util.Log.e("SyncBeatYoutube", "Service operation failed: ${error.javaClass.simpleName}")
            val code = if (job.timedOut.get()) "TIMEOUT" else if (job.cancelled.get() || error is YoutubeDL.CanceledException) "CANCELLED" else "YOUTUBE"
            val message = when (code) { "TIMEOUT" -> "Tempo massimo superato"; "CANCELLED" -> "Operazione annullata"; else -> error.message?.take(1600) ?: "Errore yt-dlp/FFmpeg" }
            deliver = { job.result.error(code, message, null) }
        } finally {
            deadline.cancel(false); cancellation.cancel(false)
            if (lock.isHeld) lock.release()
            YoutubeJobs.jobs.remove(job.id)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(startId)
            YoutubeJobs.main.post { deliver?.invoke() }
        }
    }

    private fun checkActive(job: YoutubeJob) { if (job.cancelled.get()) throw YoutubeDL.CanceledException() }
    private fun compactMetadata(output: String): String {
        val fields = listOf("id", "title", "channel", "uploader", "channel_id", "channel_url", "channel_is_verified", "duration", "thumbnail", "thumbnails", "description", "artist", "artists", "track", "album")
        return output.lineSequence().filter { it.startsWith("{") }.take(30).joinToString("\n") { line ->
            val source = JSONObject(line); val target = JSONObject()
            fields.forEach { if (source.has(it)) target.put(it, source.get(it)) }
            target.toString()
        }
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        YoutubeJobs.jobs.values.forEach { it.timedOut.set(true); YoutubeJobs.cancel(it.id) }
        stopSelf(startId)
    }
}
