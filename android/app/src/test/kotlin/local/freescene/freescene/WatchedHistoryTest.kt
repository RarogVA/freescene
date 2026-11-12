package local.freescene.freescene

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class WatchedHistoryTest {
    @Test fun onlyRealPlaybackReachesOneMinuteAndMarksOnce() {
        var marks = 0
        val clock = WatchedClock { marks++ }
        clock.sample(true, 0)
        for (second in 1..29) clock.sample(true, second * 1000L)
        clock.sample(false, 30000)
        assertEquals(30000L, clock.elapsed)
        clock.sample(false, 240000) // loading, paused, or backgrounded
        clock.sample(true, 241000)
        for (second in 1..29) clock.sample(true, 241000 + second * 1000L)
        assertEquals(59000L, clock.elapsed)
        assertEquals(0, marks)
        clock.sample(true, 271000)
        assertEquals(1, marks)
        clock.sample(true, 272000)
        assertEquals(1, marks)
        val otherSource = WatchedClock { marks++ }
        otherSource.sample(true, 0)
        otherSource.sample(true, 1000000) // stale callback never counts as playback
        assertEquals(0L, otherSource.elapsed)
    }
    @Test fun webReportsCountWallTimeNotSeekPositions() {
        val context = RuntimeEnvironment.getApplication()
        var marks = 0
        val clock = WatchedClock {
            WatchedHistory(context).set("web-source", "web-film", true); marks++
        }
        val bridge = WebPlaybackProgress(received = { _, _ -> }, playing = { clock.sample(it) })
        fun report(position: Long, playing: Boolean) {
            bridge.postMessage("""{"position":$position,"duration":7200000,"playing":$playing}""")
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        }
        report(0, true)
        repeat(30) {
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))
            report(1000L * it, true)
        }
        report(3600000, false) // Seek to an hour does not earn an hour of viewing.
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(90))
        report(3600000, false)
        assertEquals(0, marks)
        report(3600000, true)
        repeat(30) {
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))
            report(3600000L + it * 1000, true)
        }
        assertEquals(1, marks)
        assertEquals("web-film", WatchedHistory(context).snapshot()["web-source"])
    }
    @Test fun persistedVariantsCanBeClearedIndependently() {
        val context = RuntimeEnvironment.getApplication()
        WatchedHistory(context).set("source-a", "film", true)
        WatchedHistory(context).set("source-b", "film", true)
        val restored = WatchedHistory(context)
        assertEquals("film", restored.snapshot()["source-a"])
        restored.set("source-a", "film", false)
        assertNull(restored.snapshot()["source-a"])
        assertEquals("film", restored.snapshot()["source-b"])
    }
    @Test fun lightAndDarkPlayerAccentsFollowSavedAppearance() {
        val context = RuntimeEnvironment.getApplication()
        PlayerColors.configure(context, false)
        assertEquals(android.graphics.Color.rgb(82, 99, 199), PlayerColors.accent)
        PlayerColors.restore(context)
        assertEquals(android.graphics.Color.rgb(82, 99, 199), PlayerColors.accent)
        PlayerColors.configure(context, true)
        assertEquals(android.graphics.Color.rgb(221, 166, 108), PlayerColors.accent)
    }
}
