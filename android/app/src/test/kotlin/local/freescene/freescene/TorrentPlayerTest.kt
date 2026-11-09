package local.freescene.freescene

import android.content.Intent
import android.os.Looper
import android.view.KeyEvent
import android.widget.TextView
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlertDialog
import org.robolectric.annotation.Config
import java.time.Duration

class FixtureTorrentPlayer : PlayerActivity() {
    val commands = mutableListOf<String>()
    var media: String? = null
    override fun startTorrentService() {}
    override fun startMedia(url: String) { media = url }
    override fun request(method: String, extra: JSONObject, callback: (Result<JSONObject>) -> Unit) {
        commands.add(method)
        val data = when (method) {
            "status" -> JSONObject("""{"tasks":[{"id":"${"a".repeat(40)}","metadata":true,"files":[{"index":0,"name":"S01E01.mp4","video":true},{"index":1,"name":"S01E02.mkv","video":true},{"index":2,"name":"README.txt","video":false}]}]}""")
            "stream" -> JSONObject().put("url", "http://127.0.0.1:8000/fixture/${extra.getInt("file")}")
            else -> JSONObject()
        }
        callback(Result.success(data))
    }
}
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TorrentPlayerTest {
    @Test fun playerOpensBeforeEpisodePickerAndClosePausesTorrent() {
        val controller = Robolectric.buildActivity(FixtureTorrentPlayer::class.java,
            Intent(RuntimeEnvironment.getApplication(), FixtureTorrentPlayer::class.java).putExtra("torrentId", "a".repeat(40)))
            .create().start().resume().visible()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10))
        val activity = controller.get()
        val dialog = ShadowAlertDialog.getLatestAlertDialog()
        assertTrue(dialog.isShowing)
        assertEquals(2, dialog.listView.count)
        assertEquals(0, dialog.listView.checkedItemPosition)
        assertNull(activity.media)
        assertTrue(activity.commands.contains("prepareStream"))
        dialog.listView.performItemClick(dialog.listView.getChildAt(1), 1, 1)
        // Android delivers OnDismiss before the next physical remote press.
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("http://127.0.0.1:8000/fixture/1", activity.media)
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
        if (TvWindow.isTv(activity)) {
            assertFalse(activity.isFinishing)
            assertFalse(activity.commands.contains("pause"))
            assertFalse(activity.commands.contains("closeStream"))
            assertEquals("http://127.0.0.1:8000/fixture/1", activity.media)
            activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
            activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
        }
        assertTrue(activity.isFinishing)
        controller.pause().stop().destroy()
        assertTrue(activity.commands.contains("pause"))
        assertEquals(if (TvWindow.isTv(activity)) "closeStream" else "pause", activity.commands.last())
    }
    @Test fun tvDoesNotExposeBackgroundDownloadCommands() {
        org.junit.Assume.assumeTrue(BuildConfig.FLAVOR == "tv")
        val activity = Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
        val channel = TorrentChannel(activity)
        for (method in listOf("torrentAdd", "torrentImport", "torrentPlay", "torrentCommand")) {
            var error: String? = null
            channel.call(io.flutter.plugin.common.MethodCall(method, null), object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) { fail("TV allowed a download command") }
                override fun error(code: String, message: String?, details: Any?) { error = code }
                override fun notImplemented() { fail("Expected explicit playback-only guard") }
            })
            assertEquals("playback_only", error)
        }
        TorrentService.start(activity)
        assertNull(shadowOf(activity).nextStartedService)
    }
    @Test fun backgroundingPausesWithoutDiscardingEpisodeForReturn() {
        val controller = Robolectric.buildActivity(FixtureTorrentPlayer::class.java,
            Intent(RuntimeEnvironment.getApplication(), FixtureTorrentPlayer::class.java).putExtra("torrentId", "a".repeat(40)))
            .create().start().resume().visible()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10))
        controller.pause().stop()
        assertEquals("pause", controller.get().commands.last())
        assertFalse(controller.get().commands.contains("closeStream"))
        controller.destroy()
    }
    @Test fun untrustedLoopbackDoesNotBecomeGeneralPlayerInput() {
        assertFalse(PlaybackPolicy.allowed("http://127.0.0.1:8000/other"))
        assertFalse(TorrentEngine.trustedStream("http://127.0.0.1:8000/other"))
        assertTrue(TorrentPolicy.magnet("magnet:?xt=urn:btih:" + "a".repeat(40)))
        assertFalse(TorrentPolicy.magnet("file:///private/file"))
        assertFalse(TorrentPolicy.magnet("magnet:?xt=invalid"))
        assertFalse(TorrentPolicy.id("../file"))
    }
}
