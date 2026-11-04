package com.example.syncbeat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Intent
import android.os.Build
import android.media.MediaPlayer
import java.io.File

class MainActivity : FlutterActivity() {
    private val publicAudio by lazy { PublicAudioBridge(this) }
    private var player: MediaPlayer? = null
    private var pendingPlayback: MethodChannel.Result? = null
    private var playbackError: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "syncbeat/public_audio").setMethodCallHandler { call, result ->
            try {
                @Suppress("UNCHECKED_CAST")
                publicAudio.handle(call.method, call.arguments as? Map<String, Any> ?: emptyMap(), result)
            } catch (error: Exception) { result.error("STORAGE", error.message, null) }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "syncbeat/youtube/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { YoutubeJobs.events = events }
            override fun onCancel(arguments: Any?) { YoutubeJobs.events = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "syncbeat/youtube").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "licenses" -> result.success(assets.open("licenses/NOTICE.txt").bufferedReader().use { it.readText() } + "\n\n" + assets.open("licenses/youtubedl-android-GPL-3.0.txt").bufferedReader().use { it.readText() })
                    "run" -> {
                        android.util.Log.i("SyncBeatYoutube", "Native operation requested")
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4102)
                        }
                        val id = requireNotNull(call.argument<String>("id"))
                        val args = requireNotNull(call.argument<List<String>>("arguments"))
                        val timeout = requireNotNull(call.argument<Number>("timeoutMs")).toLong()
                        YoutubeRequestPolicy.validate(id, args, timeout, listOf(filesDir, cacheDir))
                        android.util.Log.i("SyncBeatYoutube", "Policy accepted; search=${args.contains("--dump-json")}")
                        synchronized(YoutubeJobs.jobs) {
                            check(YoutubeJobs.jobs.isEmpty()) { "Un’operazione YouTube è già in corso" }
                            YoutubeJobs.jobs[id] = YoutubeJob(id, args, timeout, result)
                        }
                        try {
                            val intent = Intent(this, YoutubeOperationService::class.java).putExtra("id", id)
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        } catch (error: Exception) { YoutubeJobs.jobs.remove(id); throw error }
                    }
                    "cancel" -> { YoutubeJobs.cancel(requireNotNull(call.argument<String>("id"))); result.success(null) }
                    "play" -> {
                        val path = requireNotNull(call.argument<String>("path"))
                        val uri = if (path.startsWith("content://")) publicAudio.playbackUri(path) else null
                        val file = if (uri == null) YoutubeRequestPolicy.requirePrivate(File(path), listOf(filesDir)) else null
                        if (file != null) require(file.extension.lowercase() == "mp3" && file.isFile) { "File MP3 non valido" }
                        player?.release()
                        pendingPlayback?.error("CANCELLED", "Riproduzione sostituita", null)
                        pendingPlayback = result
                        playbackError = null
                        player = MediaPlayer().apply {
                            if (uri != null) setDataSource(this@MainActivity, uri) else setDataSource(file!!.path)
                            setOnPreparedListener {
                                if (pendingPlayback === result) {
                                    pendingPlayback = null
                                    try { it.start(); result.success(null) }
                                    catch (error: Exception) { playbackError = error.message; result.error("PLAYBACK", playbackError, null) }
                                }
                            }
                            setOnErrorListener { _, what, extra ->
                                playbackError = "Errore audio $what/$extra"
                                if (pendingPlayback === result) { pendingPlayback = null; result.error("PLAYBACK", playbackError, null) }
                                true
                            }
                            prepareAsync()
                        }
                    }
                    "stop" -> { pendingPlayback?.error("CANCELLED", "Riproduzione fermata", null); pendingPlayback = null; player?.release(); player = null; result.success(null) }
                    "playbackState" -> result.success(mapOf("playing" to (player?.isPlaying ?: false), "positionMs" to (player?.currentPosition ?: 0), "durationMs" to (player?.duration ?: 0), "error" to playbackError))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                android.util.Log.e("SyncBeatYoutube", "Native request failed: ${error.javaClass.simpleName}")
                if (pendingPlayback === result) pendingPlayback = null
                result.error("ANDROID", error.message, null)
            }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!publicAudio.onActivityResult(requestCode, resultCode, data)) super.onActivityResult(requestCode, resultCode, data)
    }
    override fun onDestroy() { player?.release(); player = null; super.onDestroy() }
}
