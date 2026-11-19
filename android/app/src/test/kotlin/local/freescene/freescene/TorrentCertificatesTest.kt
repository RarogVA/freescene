package local.freescene.freescene

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TorrentCertificatesTest {
    @get:Rule val folder = TemporaryFolder()
    @Test fun certificatePathSurvivesProbeAndPlaybackCleanupAndRefreshesInPlace() {
        val files = folder.newFolder("files")
        val cache = folder.newFolder("cache")
        File(cache, "source-probe").mkdirs()
        File(cache, "tv-playback").mkdirs()
        val ca = TorrentCertificates.publish(files, "first certificate")
        cache.deleteRecursively()
        assertEquals("first certificate", ca.readText())
        assertEquals(ca, TorrentCertificates.publish(files, "updated certificates"))
        assertEquals("updated certificates", ca.readText())
        assertFalse(File(files, "torrent-ca.pem.tmp").exists())
    }
    @Test fun emptyExportDoesNotReplaceExistingCertificates() {
        val files = folder.newFolder("files")
        val ca = TorrentCertificates.publish(files, "valid certificates")
        try { TorrentCertificates.publish(files, ""); fail("Expected empty store rejection") }
        catch (_: IllegalStateException) { }
        assertEquals("valid certificates", ca.readText())
    }
}
