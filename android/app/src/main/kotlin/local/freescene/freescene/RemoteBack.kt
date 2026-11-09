package local.freescene.freescene

import android.view.KeyEvent

/** A physical press, including repeats, produces exactly one system back. */
class RemoteBack {
    private var pressed = false
    fun dispatch(event: KeyEvent, back: () -> Unit): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_BACK) return false
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) pressed = true
        if (event.action == KeyEvent.ACTION_UP) {
            val invoke = pressed && !event.isCanceled
            pressed = false
            if (invoke) back()
        }
        return true
    }
}
