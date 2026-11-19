package local.freescene.freescene

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TorrentEpisodeTest {
    private fun files(vararg names: String) = names.mapIndexed { i, name -> JSONObject().put("name", name).put("index", i) }
    @Test fun probeNeverSubstitutesFirstEpisodeForRequestedEpisode() {
        val videos = files("Show.S01E01.mkv", "Show.S01E04.mkv")
        assertEquals(1, TorrentEpisode.probeIndex(videos, 1, 4))
        assertNull(TorrentEpisode.probeIndex(videos, 1, 3))
        assertNull(TorrentEpisode.probeIndex(files("Show.04.mkv"), 1, 4))
        assertEquals(0, TorrentEpisode.probeIndex(videos, -1, -1))
    }
    @Test fun selectedSeasonAndEpisodeMatchAcrossASeasonPack() {
        val files = files("Show.S01E01.mkv", "Show.S01E02.mkv", "Show.S02E02.mkv")
        assertEquals(1, TorrentEpisode.index(files, 1, 2))
        assertEquals(2, TorrentEpisode.index(files, 2, 2))
        assertNull(TorrentEpisode.index(files, -1, 2))
        assertEquals(0, TorrentEpisode.index(files, -1, 1))
        assertEquals(0, TorrentEpisode.index(files("Show.1x02.mkv"), 1, 2))
    }
    @Test fun ambiguousOrUnrecognizedFilesRequireManualChoice() {
        for (names in listOf(arrayOf("Show.S01E02.1080.mkv", "Show.S01E02.720.mkv"),
            arrayOf("Show.S01E02E03.mkv"), arrayOf("Show.S01E02-03.mkv"),
            arrayOf("Show.S01E02.S01E03.mkv"), arrayOf("Show.1x02x03.mkv"),
            arrayOf("Show.S01E01E02.S01E02.mkv"), arrayOf("Show.S01E02 - 03.mkv"),
            arrayOf("Show.S01E020.mkv"), arrayOf("Show.02.mkv"))) {
            assertNull(TorrentEpisode.index(files(*names), 1, 2))
        }
        assertNull(TorrentEpisode.index(files("Show.S01E02.mkv"), 1, -1))
    }
}
