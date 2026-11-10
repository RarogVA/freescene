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
    @Test fun onlyRealPlaybackReachesTwoMinutesAndMarksOnce() {
        var marks = 0
        val clock = WatchedClock { marks++ }
        clock.sample(true, 0)
        for (second in 1..119) clock.sample(true, second * 1000L)
        assertEquals(0, marks)
        clock.sample(false, 120000)
        clock.sample(false, 240000) // loading, paused, or backgrounded
        clock.sample(true, 241000)
        assertEquals(0, marks)
        clock.sample(true, 242000)
        assertEquals(1, marks)
        clock.sample(true, 243000)
        assertEquals(1, marks)
        val otherSource = WatchedClock { marks++ }
        otherSource.sample(true, 0)
        otherSource.sample(true, 1000000) // stale callback never counts as playback
        assertEquals(0L, otherSource.elapsed)
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
