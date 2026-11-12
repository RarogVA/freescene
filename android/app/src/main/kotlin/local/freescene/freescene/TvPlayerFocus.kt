package local.freescene.freescene

import android.view.View

/** Restore only usable controls. A disabled time bar is not a focus destination. */
internal class TvPlayerFocus(private val root: View, private val primary: () -> View?) {
    private var previous: View? = null
    private var initial = false
    private fun usable(view: View?) = view != null && view !== root && view.isAttachedToWindow &&
        view.isShown && view.isEnabled && view.isFocusable

    fun remember() {
        root.findFocus()?.takeIf(::usable)?.let { previous = it }
    }

    fun restore(force: Boolean = false) {
        val current = root.findFocus()
        if (!force && initial && usable(current)) return
        val target = if (!initial) primary() else previous?.takeIf(::usable) ?: primary()
        if (usable(target) && target!!.requestFocus()) {
            initial = true
            previous = target
        }
    }

    fun moved() {
        root.findFocus()?.takeIf(::usable)?.let { previous = it; initial = true }
    }
}
