package local.freescene.freescene

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.ImageButton

/** Compact exit control shared by native and embedded players. */
class PlayerCloseButton(context: Context) : ImageButton(context) {
    val diameter = (48 * resources.displayMetrics.density).toInt()
    init {
        id = View.generateViewId()
        // A focusable-in-touch-mode button consumes the first tap to take focus.
        isFocusableInTouchMode = TvWindow.isTv(context)
        contentDescription = if (resources.configuration.locales[0].language == "ru") "Закрыть" else "Close"
        setImageResource(R.drawable.ic_player_close)
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) }
        val states = arrayOf(intArrayOf(android.R.attr.state_pressed), intArrayOf(android.R.attr.state_focused), intArrayOf())
        backgroundTintList = ColorStateList(states,
            intArrayOf(PlayerColors.accent, PlayerColors.accent, PlayerColors.raised))
        imageTintList = ColorStateList(states,
            intArrayOf(PlayerColors.onAccent, PlayerColors.onAccent, PlayerColors.text))
        if (TvWindow.isTv(context)) {
            TvButtonFocus.apply(this, circle = true)
            imageTintList = ColorStateList.valueOf(PlayerColors.text)
        }
        val inset = (12 * resources.displayMetrics.density).toInt()
        setPadding(inset, inset, inset, inset)
    }
}
