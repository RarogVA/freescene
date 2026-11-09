package local.freescene.freescene

import android.view.KeyEvent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class RemoteBackTest {
    @Test fun pressAndHoldProduceOneBackOnlyOnRelease() {
        val gate = RemoteBack(); var calls = 0
        assertTrue(gate.dispatch(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK, 0)) { calls++ })
        gate.dispatch(KeyEvent(0, 10, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK, 1)) { calls++ }
        assertEquals(0, calls)
        gate.dispatch(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)) { calls++ }
        gate.dispatch(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)) { calls++ }
        assertEquals(1, calls)
        gate.dispatch(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)) { calls++ }
        gate.dispatch(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)) { calls++ }
        assertEquals(2, calls)
        assertFalse(gate.dispatch(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER)) { calls++ })
    }
}
