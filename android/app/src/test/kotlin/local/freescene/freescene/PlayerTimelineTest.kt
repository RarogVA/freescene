package local.freescene.freescene

import android.content.Intent
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import androidx.media3.common.C
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.TimeBar
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlayerTimelineTest {
    @Test fun tapsUseTenSecondsAndHeldStepsAccelerateInBothDirectionsUntilRelease() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withTimeline { activity, bar, scrub ->
            bar.setPosition(600000)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            assertEquals(610000L, scrub.position)
            var expected = 610000L
            for ((index, sample) in listOf(500L to 60000L, 1000L to 60000L, 2000L to 120000L,
                    4000L to 180000L, 6000L to 240000L, 8000L to 300000L, 20000L to 300000L).withIndex()) {
                key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = index + 1, heldMs = sample.first)
                expected += sample.second
                assertEquals(expected, scrub.position)
            }
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, action = KeyEvent.ACTION_UP)
            assertEquals(expected, scrub.position)
            key(activity, KeyEvent.KEYCODE_DPAD_LEFT)
            expected -= 10000
            assertEquals(expected, scrub.position)
            key(activity, KeyEvent.KEYCODE_DPAD_LEFT, repeat = 1, heldMs = 500)
            expected -= 60000
            assertEquals(expected, scrub.position)
            key(activity, KeyEvent.KEYCODE_DPAD_LEFT, repeat = 2, heldMs = 2000)
            expected -= 120000
            assertEquals(expected, scrub.position)
            key(activity, KeyEvent.KEYCODE_DPAD_LEFT, action = KeyEvent.ACTION_UP)
            key(activity, KeyEvent.KEYCODE_DPAD_LEFT)
            expected -= 10000
            assertEquals(expected, scrub.position)
            key(activity, KeyEvent.KEYCODE_DPAD_LEFT, action = KeyEvent.ACTION_UP)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
            assertEquals(listOf(expected), scrub.stops)
            assertTrue(bar.hasFocus())
        }
    }

    @Test fun fastRemoteRepeatsCannotSkipMoreOftenThanTwicePerSecond() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withTimeline { activity, bar, scrub ->
            bar.setPosition(600000)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 1, heldMs = 500)
            assertEquals(670000L, scrub.position)
            for (heldMs in listOf(550L, 600L, 750L, 999L)) {
                key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 2, heldMs = heldMs)
                assertEquals(670000L, scrub.position)
            }
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 3, heldMs = 1000)
            assertEquals(730000L, scrub.position)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, action = KeyEvent.ACTION_UP)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 1, heldMs = 500)
            assertEquals(800000L, scrub.position)
        }
    }

    @Test fun heldSeekClampsToVideoBoundsAndKeepsTimelineFocus() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        for ((key, expected) in listOf(KeyEvent.KEYCODE_DPAD_LEFT to 0L, KeyEvent.KEYCODE_DPAD_RIGHT to 30000L)) {
            withTimeline { activity, bar, scrub ->
                bar.setDuration(30000); bar.setPosition(15000)
                key(activity, key)
                key(activity, key, repeat = 1)
                key(activity, key, repeat = 2)
                key(activity, key, action = KeyEvent.ACTION_UP)
                assertEquals(expected, scrub.position)
                assertTrue(bar.hasFocus())
            }
        }
    }

    @Test fun unknownDurationAndOtherFocusedControlsDoNotSeek() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withTimeline { activity, bar, scrub ->
            bar.setDuration(C.TIME_UNSET)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 1)
            assertNull(scrub.position)
            bar.setDuration(3600000)
            activity.window.decorView.findViewWithTag<View>("player-close").requestFocus()
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            assertNull(scrub.position)
        }
    }

    @Test fun accessibilityStillUsesTenSecondsAfterHeldSeek() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withTimeline { activity, bar, scrub ->
            bar.setPosition(600000)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 1)
            bar.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, null)
            assertEquals(680000L, scrub.position)
            assertEquals(listOf(680000L), scrub.stops)
        }
    }

    @Test fun phoneDoesNotAdoptTvHeldSeekSteps() {
        assumeTrue(BuildConfig.FLAVOR == "mobile")
        withTimeline { activity, bar, scrub ->
            bar.setPosition(600000)
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT)
            val first = scrub.position!!
            key(activity, KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 1)
            assertEquals(first - 600000, scrub.position!! - first)
            assertEquals(180000L, first - 600000) // Existing 1/20-duration keyboard step.
        }
    }

    private fun key(activity: PlayerActivity, code: Int, repeat: Int = 0, action: Int = KeyEvent.ACTION_DOWN,
                    heldMs: Long = if (repeat > 0) 500 else 0) {
        val now = SystemClock.uptimeMillis()
        activity.dispatchKeyEvent(KeyEvent(now, now + heldMs, action, code, repeat))
    }

    private fun withTimeline(test: (PlayerActivity, DefaultTimeBar, Scrub) -> Unit) {
        val controller = Robolectric.buildActivity(UiOnlyPlayerActivity::class.java,
            Intent(RuntimeEnvironment.getApplication(), UiOnlyPlayerActivity::class.java)
                .putExtra("url", "https://127.0.0.1/fixture.m3u8"))
            .setup().windowFocusChanged(true)
        try {
            val activity = controller.get()
            val bar = activity.findViewById<DefaultTimeBar>(androidx.media3.ui.R.id.exo_progress)
            bar.isEnabled = true; bar.isFocusableInTouchMode = true
            bar.setDuration(3600000); assertTrue(bar.requestFocus())
            val scrub = Scrub(); bar.addListener(scrub)
            test(activity, bar, scrub)
        } finally { controller.pause().stop().destroy() }
    }

    private class Scrub : TimeBar.OnScrubListener {
        var position: Long? = null
        val stops = mutableListOf<Long>()
        override fun onScrubStart(timeBar: TimeBar, position: Long) { this.position = position }
        override fun onScrubMove(timeBar: TimeBar, position: Long) { this.position = position }
        override fun onScrubStop(timeBar: TimeBar, position: Long, canceled: Boolean) {
            assertFalse(canceled); stops.add(position)
        }
    }
}
