package local.freescene.freescene

import android.os.Looper
import android.view.KeyEvent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvIdleControlsTest {
    private fun advance(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
    private fun key(action: Int, code: Int = KeyEvent.KEYCODE_DPAD_CENTER) = KeyEvent(action, code)

    @Test fun hidesAtFourSecondsAndEveryRemoteEventRestartsTheClock() {
        val events = mutableListOf<Boolean>()
        val controls = TvIdleControls(true) { events.add(it) }
        controls.start()
        advance(3999); assertTrue(controls.visible)
        controls.dispatch(key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_RIGHT))
        advance(3999); assertTrue(controls.visible)
        controls.dispatch(key(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_RIGHT))
        advance(3999); assertTrue(controls.visible)
        advance(1); assertFalse(controls.visible)
        assertEquals(listOf(false), events)
        controls.stop()
    }

    @Test fun wakeConsumesEntireOkPressIncludingRepeatsButNeverBack() {
        val controls = TvIdleControls(true) {}
        controls.start(); advance(4000)
        assertTrue(controls.dispatch(key(KeyEvent.ACTION_DOWN)))
        assertTrue(controls.visible)
        assertTrue(controls.dispatch(key(KeyEvent.ACTION_DOWN)))
        assertTrue(controls.dispatch(key(KeyEvent.ACTION_UP)))
        assertFalse(controls.dispatch(key(KeyEvent.ACTION_DOWN)))
        assertFalse(controls.dispatch(key(KeyEvent.ACTION_UP)))
        advance(4000)
        assertFalse(controls.dispatch(key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
        assertFalse(controls.dispatch(key(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)))
        controls.stop()
    }

    @Test fun pauseCancelsTimerAndResumeRestartsItWithoutStaleCallbacks() {
        val events = mutableListOf<Boolean>()
        val controls = TvIdleControls(true) { events.add(it) }
        controls.start(); advance(3000); controls.stop(); advance(10000)
        assertTrue(events.isEmpty())
        controls.start(); advance(4000); assertEquals(listOf(false), events)
        controls.stop(); controls.start(); assertTrue(controls.visible)
        controls.stop(); advance(10000); assertEquals(listOf(false, true), events)
    }

    @Test fun mobileIsUnchangedAndMediaKeysStillExecuteWhenControlsAreHidden() {
        val mobile = TvIdleControls(false) { fail("Mobile controls must not change") }
        mobile.start(); advance(5000); assertTrue(mobile.visible)
        assertFalse(mobile.dispatch(key(KeyEvent.ACTION_DOWN)))
        val tv = TvIdleControls(true) {}
        tv.start(); advance(4000)
        assertFalse(tv.dispatch(key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)))
        assertTrue(tv.visible)
        tv.stop()
    }
}
