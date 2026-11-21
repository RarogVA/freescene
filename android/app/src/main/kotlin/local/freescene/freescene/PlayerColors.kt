package local.freescene.freescene

import android.graphics.Color
import android.content.Context

/** Dark video surfaces with the currently selected catalogue accent. */
object PlayerColors {
    val background: Int = Color.rgb(27, 27, 29)
    val panel: Int = Color.rgb(35, 35, 37)
    val raised: Int = Color.rgb(48, 48, 51)
    val text: Int = Color.rgb(238, 238, 240)
    var accent: Int = Color.rgb(189, 179, 255); private set
    var onAccent: Int = Color.rgb(36, 29, 70); private set
    fun configure(context: Context, dark: Boolean) {
        context.getSharedPreferences("player-appearance", Context.MODE_PRIVATE).edit().putBoolean("dark", dark).apply()
        restore(context)
    }
    fun restore(context: Context) {
        val dark = context.getSharedPreferences("player-appearance", Context.MODE_PRIVATE).getBoolean("dark", true)
        accent = if (dark) Color.rgb(189, 179, 255) else Color.rgb(103, 85, 182)
        onAccent = if (dark) Color.rgb(36, 29, 70) else Color.WHITE
    }
}
