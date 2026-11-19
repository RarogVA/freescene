package local.freescene.freescene

import android.content.Intent
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowAlertDialog

class EpisodeSelectionActivity : PlayerActivity() {
    var opened: Int? = null
    override fun startTorrentService() {}
    override fun request(method: String, extra: JSONObject, callback: (Result<JSONObject>) -> Unit) {
        when (method) {
            "prepareStream" -> callback(Result.success(JSONObject()))
            "status" -> {
                val files = JSONArray()
                for (i in 1..2) files.put(JSONObject().put("index", i - 1)
                    .put("name", "Show.S01E0$i.mkv").put("video", true))
                val task = JSONObject().put("id", intent.getStringExtra("torrentId"))
                    .put("metadata", true).put("files", files)
                callback(Result.success(JSONObject().put("tasks", JSONArray().put(task))))
            }
            "stream" -> opened = extra.getInt("file") // No decoder or network is started.
        }
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlayerEpisodeSelectionTest {
    @Test fun explicitEpisodeOverridesLastWatchedFile() {
        val app = RuntimeEnvironment.getApplication()
        val id = "a".repeat(40)
        PlaybackHistory(app).rememberTorrentFile(id, 0)
        val controller = Robolectric.buildActivity(EpisodeSelectionActivity::class.java,
            Intent(app, EpisodeSelectionActivity::class.java).putExtra("torrentId", id)
                .putExtra("series", true).putExtra("season", 1).putExtra("episode", 2)).setup()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, controller.get().opened)
        assertNull(ShadowAlertDialog.getLatestAlertDialog())
        controller.pause().stop().destroy()
    }
    @Test fun exactHistoryFileTakesPriorityOverCatalogEpisodeHint() {
        val app = RuntimeEnvironment.getApplication()
        val controller = Robolectric.buildActivity(EpisodeSelectionActivity::class.java,
            Intent(app, EpisodeSelectionActivity::class.java).putExtra("torrentId", "c".repeat(40))
                .putExtra("series", true).putExtra("season", 1).putExtra("episode", 2)
                .putExtra("historyReplay", true).putExtra("torrentFile", 0)).setup()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, controller.get().opened)
        assertNull(ShadowAlertDialog.getLatestAlertDialog())
        controller.pause().stop().destroy()
    }
    @Test fun missingHistoryFileDoesNotFallBackToAnotherEpisode() {
        val app = RuntimeEnvironment.getApplication()
        val controller = Robolectric.buildActivity(EpisodeSelectionActivity::class.java,
            Intent(app, EpisodeSelectionActivity::class.java).putExtra("torrentId", "d".repeat(40))
                .putExtra("series", true).putExtra("season", 1).putExtra("episode", 2)
                .putExtra("historyReplay", true).putExtra("torrentFile", 9)).setup()
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(controller.get().opened)
        assertNull(ShadowAlertDialog.getLatestAlertDialog())
        controller.pause().stop().destroy()
    }
    @Test fun missingEpisodeDoesNotSilentlyResumeTheOldFile() {
        val app = RuntimeEnvironment.getApplication()
        val id = "b".repeat(40)
        PlaybackHistory(app).rememberTorrentFile(id, 0)
        val controller = Robolectric.buildActivity(EpisodeSelectionActivity::class.java,
            Intent(app, EpisodeSelectionActivity::class.java).putExtra("torrentId", id)
                .putExtra("series", true).putExtra("season", 1).putExtra("episode", 3)).setup()
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(controller.get().opened)
        assertTrue(ShadowAlertDialog.getLatestAlertDialog().isShowing)
        controller.pause().stop().destroy()
    }
}
