package local.freescene.freescene

import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.widget.TextView

/** Non-focusable title: shares the player's control visibility and never steals D-pad input. */
class PlayerTitleView(context: Context, title: String?) : TextView(context) {
    init {
        tag = "player-title"
        text = title?.takeIf { it.isNotBlank() } ?: "FreeScene"
        setTextColor(PlayerColors.text)
        textSize = 20f
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER_VERTICAL
        isFocusable = false
    }
}
