package local.freescene.freescene

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.drawable.ColorDrawable
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

/** Private, bounded history keyed by media identity, never by a temporary stream URL. */
class PlaybackHistory(context: Context) {
    private val prefs = context.getSharedPreferences("playback-history", Context.MODE_PRIVATE)
    data class Point(val position: Long, val duration: Long)

    fun read(key: String): Point? = try {
        val data = JSONObject(prefs.getString(digest(key), null) ?: "{}")
        Point(data.getLong("position"), data.getLong("duration")).takeIf {
            it.position in 1000..MAX_TIME && it.duration in 0..MAX_TIME
        }
    } catch (_: Exception) { null }

    fun save(key: String, position: Long, duration: Long, ended: Boolean = false) {
        if (position !in 0..MAX_TIME || duration !in 0..MAX_TIME) return
        if (ended || (duration > 0 && position >= duration)) { clear(key); return }
        if (position < 1000) return
        val entry = JSONObject().put("position", position).put("duration", duration)
            .put("updated", System.currentTimeMillis()).toString()
        val editor = prefs.edit().putString(digest(key), entry)
        val entries = prefs.all.filterKeys { it.startsWith("media:") }
        if (entries.size >= 200 && !entries.containsKey(digest(key))) {
            entries.minByOrNull { (_, value) ->
                try { JSONObject(value as String).optLong("updated") } catch (_: Exception) { 0L }
            }?.let { editor.remove(it.key) }
        }
        editor.apply()
    }
    fun clear(key: String) { prefs.edit().remove(digest(key)).apply() }
    fun torrentFile(id: String): Int = prefs.getInt("torrent:$id", -1)
    fun rememberTorrentFile(id: String, file: Int) { prefs.edit().putInt("torrent:$id", file).apply() }

    companion object {
        const val MAX_TIME = 7 * 24 * 60 * 60 * 1000L
        private fun digest(key: String) = "media:" + MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        fun webKey(provider: String, source: String): String =
            local.freescene.provider_host.ProviderHost.web?.historyKey(provider, source)
                ?: "web:$provider:${source.trimEnd('/')}"

    }
}

object PlaybackResumeDialog {
    fun show(activity: Activity, position: Long, selected: (Boolean) -> Unit,
             cancelled: () -> Unit, dismissed: () -> Unit): AlertDialog {
        val ru = activity.resources.configuration.locales[0].language == "ru"
        val seconds = position / 1000
        val time = String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        return AlertDialog.Builder(activity, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle(if (ru) "Начать просмотр сначала или продолжить?" else "Start from the beginning or continue?")
            .setMessage(if (ru) "Вы остановились на $time." else "You stopped at $time.")
            .setNegativeButton(if (ru) "Сначала" else "Start over") { _, _ -> selected(false) }
            .setPositiveButton(if (ru) "Продолжить" else "Continue") { _, _ -> selected(true) }
            .create().also {
                it.setOnCancelListener { cancelled() }
                it.setOnDismissListener { dismissed() }
                it.show()
                it.window?.setBackgroundDrawable(ColorDrawable(PlayerColors.panel))
                if (TvWindow.isTv(activity)) it.getButton(AlertDialog.BUTTON_POSITIVE).requestFocus()
            }
    }
}
