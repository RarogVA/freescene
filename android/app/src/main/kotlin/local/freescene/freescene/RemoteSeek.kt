package local.freescene.freescene

import android.os.Handler
import android.os.Looper

/** Choose the final remote target before opening a potentially slow torrent range. */
internal class RemoteSeek(private val seek: (Long) -> Unit, private val preview: (Long?) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private var target: Long? = null
    private val commit = Runnable {
        val at = target ?: return@Runnable
        target = null
        preview(null)
        seek(at)
    }

    fun step(position: Long, delta: Long, duration: Long) {
        handler.removeCallbacks(commit)
        target = PlaybackPolicy.seek(target ?: position, delta, duration)
        preview(target)
    }

    // Do not submit while the key is held. Brief gaps between separate presses
    // belong to the same selection; a single tap adds only 300 ms of delay.
    fun release() {
        handler.removeCallbacks(commit)
        if (target != null) handler.postDelayed(commit, 300)
    }

    fun cancel() {
        handler.removeCallbacks(commit)
        if (target == null) return
        target = null
        preview(null)
    }
}
