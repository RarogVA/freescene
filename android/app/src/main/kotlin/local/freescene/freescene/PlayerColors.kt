package local.freescene.freescene

import android.graphics.Color
import android.content.Context

/** Dark video surfaces with the currently selected catalogue accent. */
object PlayerColors {
    val background: Int = Color.rgb(23, 24, 27)
    val panel: Int = Color.rgb(34, 36, 41)
    val raised: Int = Color.rgb(44, 46, 52)
    val text: Int = Color.rgb(238, 238, 240)
    var accent: Int = Color.rgb(221, 166, 108); private set
    var onAccent: Int = Color.rgb(36, 26, 16); private set
    fun configure(context: Context, dark: Boolean) {
        context.getSharedPreferences("player-appearance", Context.MODE_PRIVATE).edit().putBoolean("dark", dark).apply()
        restore(context)
    }
    fun restore(context: Context) {
        val dark = context.getSharedPreferences("player-appearance", Context.MODE_PRIVATE).getBoolean("dark", true)
        accent = if (dark) Color.rgb(221, 166, 108) else Color.rgb(82, 99, 199)
        onAccent = if (dark) Color.rgb(36, 26, 16) else Color.WHITE
    }
}
