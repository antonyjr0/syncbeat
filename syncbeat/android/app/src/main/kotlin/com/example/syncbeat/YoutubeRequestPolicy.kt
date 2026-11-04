package com.example.syncbeat

import java.io.File

/** Restrict the internal channel to SyncBeat's two commands and private output. */
object YoutubeRequestPolicy {
    fun validate(id: String, args: List<String>, timeoutMs: Long, roots: List<File>) {
        require(Regex("[A-Za-z0-9-]{1,80}").matches(id)) { "ID operazione non valido" }
        require(timeoutMs in 1000..900000) { "Timeout non valido" }
        if (args == listOf("--syncbeat-update-engine")) return
        require(args.size in 2..50 && args.all { it.length <= 4096 }) { "Argomenti non validi" }
        val separator = args.indexOf("--")
        require(separator >= 0 && separator < args.lastIndex) { "Destinazione mancante" }
        val urls = args.drop(separator + 1)
        if (args.contains("--dump-json")) {
            require(urls.size <= 2 && urls.all { Regex("ytsearch(5|10):.+").matches(it) }) { "Ricerca non valida" }
        } else {
            require(!args.contains("--flat-playlist")) { "Opzione riservata alla ricerca" }
            require(urls.size == 1 && Regex("https://www\\.youtube\\.com/watch\\?v=[A-Za-z0-9_-]{11}").matches(urls[0])) { "URL non valido" }
            require(args.containsAll(listOf("--extract-audio", "--audio-format", "mp3"))) { "Formato non consentito" }
            val outputIndex = args.indexOf("--output")
            require(outputIndex >= 0 && outputIndex + 1 < separator) { "Output mancante" }
            requirePrivate(File(args[outputIndex + 1]), roots)
        }
        val allowed = setOf("--dump-json", "--flat-playlist", "--skip-download", "--ignore-errors", "--format", "--extract-audio", "--audio-format", "--audio-quality", "--max-filesize", "--no-overwrites", "--newline", "--progress", "--progress-template", "--output")
        require(args.take(separator).filter { it.startsWith("--") }.all { it in allowed }) { "Opzione non consentita" }
    }

    fun requirePrivate(file: File, roots: List<File>): File {
        val canonical = file.canonicalFile
        require(roots.any { canonical.path.startsWith(it.canonicalPath + File.separator) }) { "File esterno alla directory applicativa" }
        return canonical
    }
}
