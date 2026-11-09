package local.freescene.freescene

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent

/** One inactivity clock for all app-owned TV player controls, including Close. */
class TvIdleControls(private val enabled: Boolean, private val display: (Boolean) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private var active = false
    private var wakeKey: Int? = null
    var visible = true; private set
    private val hide = Runnable {
        if (active) { visible = false; display(false) }
    }

    fun start() { if (enabled) { active = true; interact() } }
    fun stop() { active = false; wakeKey = null; handler.removeCallbacks(hide) }
    fun hideNow() {
        if (!enabled || !active || !visible) return
        handler.removeCallbacks(hide)
        wakeKey = null
        visible = false
        display(false)
    }
    fun interact() {
        if (!enabled || !active) return
        if (!visible) { visible = true; display(true) }
        handler.removeCallbacks(hide)
        handler.postDelayed(hide, 4000)
    }

    /** The first navigation press only reveals controls; it cannot click Close. */
    fun dispatch(event: KeyEvent): Boolean {
        if (!enabled || !active || event.keyCode in listOf(KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE)) return false
        val wasHidden = !visible
        interact()
        if (wakeKey == event.keyCode) {
            if (event.action == KeyEvent.ACTION_UP) wakeKey = null
            return true
        }
        if (wasHidden && event.action == KeyEvent.ACTION_DOWN && event.keyCode in navigation) {
            wakeKey = event.keyCode
            return true
        }
        return false
    }

    companion object {
        private val navigation = setOf(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A)
    }
}
