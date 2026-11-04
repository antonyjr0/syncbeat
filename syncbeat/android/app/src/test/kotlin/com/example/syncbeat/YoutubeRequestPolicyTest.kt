package com.example.syncbeat

import org.junit.Test
import org.junit.Assert.*
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import java.io.File

class YoutubeRequestPolicyTest {
    @get:Rule val temporary = TemporaryFolder()
    private val search = listOf("--dump-json", "--skip-download", "--ignore-errors", "--", "ytsearch10:Tananai VELENO", "ytsearch5:Tananai VELENO auto-generated")
    @Test fun permitsSharedSearchProtocol() { YoutubeRequestPolicy.validate("job-1", search, 180000, listOf(temporary.root)) }
    @Test fun permitsFlatSearchWithoutChangingQueryCoverage() {
        YoutubeRequestPolicy.validate("job-fast", listOf("--flat-playlist") + search, 30000, listOf(temporary.root))
    }
    @Test fun rejectsFlatModeForDownloads() {
        val output = File(temporary.root, "audio.%(ext)s")
        try {
            YoutubeRequestPolicy.validate("job-flat-download", listOf("--flat-playlist", "--extract-audio", "--audio-format", "mp3", "--output", output.path, "--", "https://www.youtube.com/watch?v=PzYnwqUGI7Q"), 30000, listOf(temporary.root))
            fail("Flat download accepted")
        } catch (_: IllegalArgumentException) { }
    }
    @Test fun permitsMp3OnlyInPrivateRoot() {
        val output = File(temporary.newFolder("cache"), "audio.%(ext)s")
        YoutubeRequestPolicy.validate("job-2", listOf("--extract-audio", "--audio-format", "mp3", "--output", output.path, "--", "https://www.youtube.com/watch?v=PzYnwqUGI7Q"), 900000, listOf(temporary.root))
    }
    @Test fun rejectsPathTraversalAndSiblingPrefix() {
        for (path in listOf(File(temporary.root, "../outside/audio.mp3"), File(temporary.root.path + "-sibling/audio.mp3"))) {
            try { YoutubeRequestPolicy.requirePrivate(path, listOf(temporary.root)); fail("Path accepted") } catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun rejectsArbitraryCommandsAndInvalidTimeout() {
        for (args in listOf(listOf("--exec", "bad", "--", "ytsearch5:music"), listOf("--dump-json", "--", "https://other.example"))) {
            try { YoutubeRequestPolicy.validate("job", args, 30000, listOf(temporary.root)); fail("Command accepted") } catch (_: IllegalArgumentException) { }
        }
        try { YoutubeRequestPolicy.validate("job", search, 9999999, listOf(temporary.root)); fail("Timeout accepted") } catch (_: IllegalArgumentException) { }
    }
}
