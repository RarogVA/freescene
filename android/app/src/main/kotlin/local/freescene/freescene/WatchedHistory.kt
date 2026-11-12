package local.freescene.freescene

import android.content.Context
import android.os.SystemClock

/** Separate from resume bookmarks: finishing a film must not erase its watched mark. */
class WatchedHistory(context: Context) {
    private val prefs = context.getSharedPreferences("watched", Context.MODE_PRIVATE)
    fun snapshot(): Map<String, String> = prefs.all.mapNotNull { (key, value) ->
        (value as? String)?.let { key to it }
    }.toMap()
    fun set(source: String?, title: String?, watched: Boolean) {
        if (source.isNullOrBlank() || title.isNullOrBlank() || source.length > 4096 || title.length > 4096) return
        val edit = prefs.edit()
        if (watched) edit.putString(source, title) else edit.remove(source)
        edit.apply()
    }
}

/** Wall-clock playback, not the playhead: seeking never earns watched time. */
class WatchedClock(private val marked: () -> Unit) {
    var elapsed = 0L
    private var last: Long? = null
    private var active = false
    fun sample(playing: Boolean, now: Long = SystemClock.elapsedRealtime()) {
        val previous = last
        if (active && previous != null && now - previous in 0..6000 && elapsed < 60000) {
            elapsed += now - previous
            if (elapsed >= 60000) marked()
        }
        active = playing
        last = now
    }
}
