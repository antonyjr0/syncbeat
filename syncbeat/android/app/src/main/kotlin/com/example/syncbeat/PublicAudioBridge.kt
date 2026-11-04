package com.example.syncbeat

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.MediaExtractor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import org.json.JSONObject

/** Public audio is published only after private conversion and validation. */
class PublicAudioBridge(private val activity: Activity) {
    private val resolver get() = activity.contentResolver
    private val preferences = activity.getSharedPreferences("public_audio", 0)
    private val worker = Executors.newSingleThreadExecutor()
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private var pending: Pair<Map<String, Any>, MethodChannel.Result>? = null

    fun handle(method: String, arguments: Map<String, Any>, result: MethodChannel.Result) {
        when (method) {
            "records" -> result.success(preferences.all.values.filterIsInstance<String>())
            "cancel" -> { cancelled.add(arguments["id"] as String); result.success(null) }
            "validate" -> background(result) { validate(privateFile(arguments)); null }
            "verify" -> background(result) {
                try {
                    val uri = owned(arguments["path"] as String)
                    if (Build.VERSION.SDK_INT >= 29 && uri.authority == "media") {
                        resolver.query(uri, arrayOf(MediaStore.MediaColumns.IS_PENDING), null, null, null)?.use { cursor ->
                            require(cursor.moveToFirst() && cursor.getInt(0) == 0) { "Pubblicazione incompleta" }
                        } ?: error("File eliminato")
                    }
                    val digest = MessageDigest.getInstance("SHA-256")
                    var size = 0L
                    resolver.openInputStream(uri)!!.use { input ->
                        val bytes = ByteArray(65536)
                        while (true) { val count = input.read(bytes); if (count < 0) break; digest.update(bytes, 0, count); size += count }
                    }
                    size == (arguments["sizeBytes"] as Number).toLong() && hex(digest.digest()) == arguments["sha256"]
                } catch (_: Exception) { false }
            }
            "publish" -> {
                if (Build.VERSION.SDK_INT >= 29) background(result) { publish(arguments, null) }
                else {
                    check(pending == null) { "Salvataggio già in corso" }
                    pending = arguments to result
                    // Android 7–9: user chooses Download, only that tree is granted.
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }, 5103)
                }
            }
            "open" -> {
                val uri = owned(arguments["path"] as String)
                activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "audio/mpeg").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                result.success(null)
            }
            "openFolder" -> {
                activity.startActivity(Intent("android.intent.action.VIEW_DOWNLOADS"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(request: Int, code: Int, intent: Intent?): Boolean {
        if (request != 5103) return false
        val job = pending ?: return true
        pending = null
        val uri = intent?.data
        if (code != Activity.RESULT_OK || uri == null) { job.second.error("CANCELLED", "Salvataggio annullato", null); return true }
        try {
            val documentId = DocumentsContract.getTreeDocumentId(uri)
            require(documentId.substringAfter(':').trimEnd('/') == "Download") { "Seleziona la cartella Download della memoria interna" }
            require(documentId.startsWith("primary:")) { "Seleziona la memoria interna" }
            resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            background(job.second) { publish(job.first, uri) }
        } catch (error: Exception) { job.second.error("STORAGE", error.message, null) }
        return true
    }

    private fun privateFile(data: Map<String, Any>): File = YoutubeRequestPolicy.requirePrivate(
        File(data["path"] as String), listOf(activity.filesDir, activity.cacheDir))

    private fun owned(path: String): Uri {
        require(path.startsWith("content://") && preferences.contains(path)) { "URI audio non appartenente a SyncBeat" }
        return Uri.parse(path)
    }

    private fun validate(file: File) {
        require(file.isFile && file.length() in 1..(120L * 1024 * 1024)) { "Dimensione MP3 non valida" }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.path)
            require(extractor.trackCount == 1 && extractor.getTrackFormat(0).getString("mime") == "audio/mpeg") { "Il file non contiene audio MP3" }
            extractor.selectTrack(0)
            val buffer = java.nio.ByteBuffer.allocate(1024 * 1024)
            var samples = 0
            while (extractor.readSampleData(buffer, 0) >= 0) {
                require(extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0) { "Audio protetto non supportato" }
                samples++
                if (!extractor.advance()) break
                buffer.clear()
            }
            require(samples > 0) { "MP3 senza frame audio" }
        } finally { extractor.release() }
    }

    private fun publish(data: Map<String, Any>, tree: Uri?): Map<String, Any> {
        val id = data["id"] as String
        val file = privateFile(data)
        validate(file)
        val name = PublicAudioPolicy.safeName(data["name"] as String, id)
        var uri = if (Build.VERSION.SDK_INT >= 29) {
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "audio/mpeg")
                put(MediaStore.MediaColumns.RELATIVE_PATH, PublicAudioPolicy.RELATIVE_PATH)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }) ?: error("Impossibile creare il file in Download")
        } else {
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(root))
            var folder: Uri? = null
            resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) if (cursor.getString(1) == "SyncBeat") folder = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
            }
            val directory = folder ?: DocumentsContract.createDocument(resolver, root, DocumentsContract.Document.MIME_TYPE_DIR, "SyncBeat")!!
            DocumentsContract.createDocument(resolver, directory, "audio/mpeg", "$name.part")!!
        }
        try {
            PublicAudioTransaction.copy(file.inputStream(), object : PendingAudioTarget {
                override fun output() = resolver.openOutputStream(uri, "w") ?: error("Scrittura non disponibile")
                override fun input() = resolver.openInputStream(uri) ?: error("Verifica non disponibile")
                override fun commit() {
                    if (Build.VERSION.SDK_INT < 29) uri = DocumentsContract.renameDocument(resolver, uri, name) ?: error("Impossibile completare il salvataggio")
                    val record = JSONObject(data["manifest"] as String).put("path", uri.toString()).put("fileName", name).toString()
                    check(preferences.edit().putString(uri.toString(), record).commit()) { "Impossibile salvare l'indice audio" }
                    if (Build.VERSION.SDK_INT >= 29) check(resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
                }
                override fun rollback() {
                    preferences.edit().remove(uri.toString()).commit()
                    if (Build.VERSION.SDK_INT >= 29) resolver.delete(uri, null, null) else DocumentsContract.deleteDocument(resolver, uri)
                }
            }, (data["sizeBytes"] as Number).toLong(), data["sha256"] as String) { cancelled.contains(id) }
            return mapOf("path" to uri.toString(), "name" to name)
        } finally { cancelled.remove(id) }
    }

    fun playbackUri(path: String): Uri = owned(path)
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try { val value = action(); activity.runOnUiThread { result.success(value) } }
            catch (error: Exception) { activity.runOnUiThread { result.error("STORAGE", error.message ?: "Errore di salvataggio", null) } }
        }
    }
}

object PublicAudioPolicy {
    const val RELATIVE_PATH = "Download/SyncBeat/"
    fun safeName(name: String, id: String): String {
        require(Regex("[0-9]{1,30}").matches(id)) { "ID pubblicazione non valido" }
        val base = name.removeSuffix(".mp3").replace(Regex("[<>:\"/\\\\|?*\\x00-\\x1F]"), "_").trim().trimEnd('.', ' ').take(100).ifBlank { "audio" }
        return "$base-$id.mp3"
    }
    fun verify(size: Long, hash: String, expectedSize: Long, expectedHash: String) {
        require(size > 0 && size == expectedSize && hash == expectedHash) { "File incompleto o integrità non valida" }
    }
}
