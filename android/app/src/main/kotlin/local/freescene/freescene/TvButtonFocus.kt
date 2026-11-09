package local.freescene.freescene

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.view.View

/** Keep a button's fill stable; the remote focus is a copper outline. */
object TvButtonFocus {
    fun apply(view: View, circle: Boolean = false, fill: Int = PlayerColors.raised) {
        if (!TvWindow.isTv(view.context)) return
        fun shape(focused: Boolean) = GradientDrawable().apply {
            if (circle) shape = GradientDrawable.OVAL
            else cornerRadius = 12 * view.resources.displayMetrics.density
            setColor(fill)
            if (focused) setStroke((3 * view.resources.displayMetrics.density).toInt(), PlayerColors.accent)
        }
        view.backgroundTintList = null
        view.background = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), shape(true))
            addState(intArrayOf(), shape(false))
        }
    }
}
