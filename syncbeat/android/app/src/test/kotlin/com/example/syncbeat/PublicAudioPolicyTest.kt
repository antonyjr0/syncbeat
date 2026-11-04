package com.example.syncbeat

import org.junit.Assert.*
import org.junit.Test

class PublicAudioPolicyTest {
    @Test fun publicDirectoryIsDownloadsSyncBeat() {
        assertEquals("Download/SyncBeat/", PublicAudioPolicy.RELATIVE_PATH)
    }
    @Test fun filenamesCannotTraverseDirectoriesAndHaveUniqueSuffix() {
        val name = PublicAudioPolicy.safeName("../bad:file?.mp3", "123")
        assertFalse(name.contains('/'))
        assertFalse(name.contains(':'))
        assertTrue(name.endsWith("-123.mp3"))
        assertNotEquals(name, PublicAudioPolicy.safeName("../bad:file?.mp3", "124"))
    }
    @Test fun completeCopyHasMatchingSizeAndHash() {
        PublicAudioPolicy.verify(100, "hash", 100, "hash")
    }
    @Test fun incompleteOrCorruptCopyCannotCommit() {
        for (pair in listOf(99L to "hash", 100L to "bad", 0L to "hash")) {
            try { PublicAudioPolicy.verify(pair.first, pair.second, 100, "hash"); fail("Must reject incomplete data") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
