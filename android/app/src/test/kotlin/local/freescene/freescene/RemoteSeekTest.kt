package local.freescene.freescene

import android.content.Intent
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.lang.reflect.Proxy
import java.time.Duration

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class RemoteSeekTest {
    private fun advance(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))

    @Test fun twelveTapsMakeOneSeekAndPreviewEveryStepWithoutPlaybackDrift() {
        val seeks = mutableListOf<Long>(); val previews = mutableListOf<Long?>()
        val remote = RemoteSeek(seeks::add, previews::add)
        repeat(12) { index ->
            remote.step(30000L + index * 100, 10000, 600000)
            remote.release(); advance(100)
        }
        assertTrue(seeks.isEmpty())
        assertEquals(150000L, previews.last())
        advance(199); assertTrue(seeks.isEmpty())
        advance(1); assertEquals(listOf(150000L), seeks)
        assertNull(previews.last())
        remote.step(155000, -10000, 600000); remote.release(); advance(300)
        assertEquals(listOf(150000L, 145000L), seeks)
    }

    @Test fun heldKeyDoesNotCommitUntilReleaseAndDirectionCanBeCorrected() {
        val seeks = mutableListOf<Long>(); val remote = RemoteSeek(seeks::add) {}
        remote.step(30000, 10000, 600000); advance(1000)
        remote.step(31000, 10000, 600000); advance(500)
        remote.step(31500, -10000, 600000); advance(500)
        assertTrue(seeks.isEmpty())
        remote.release(); advance(300)
        assertEquals(listOf(40000L), seeks)
    }

    @Test fun boundsAndUnknownDurationArePreserved() {
        val seeks = mutableListOf<Long>(); val remote = RemoteSeek(seeks::add) {}
        remote.step(1000, -10000, 30000); remote.release(); advance(300)
        remote.step(25000, 10000, 30000); remote.release(); advance(300)
        remote.step(25000, 10000, androidx.media3.common.C.TIME_UNSET); remote.release(); advance(300)
        assertEquals(listOf(0L, 30000L, 35000L), seeks)
    }

    @Test fun canceledSelectionCannotSeekTheNextVideo() {
        val seeks = mutableListOf<Long>(); val remote = RemoteSeek(seeks::add) {}
        remote.step(30000, 10000, 600000); remote.release(); advance(200)
        remote.cancel(); advance(1000); assertTrue(seeks.isEmpty())
        remote.step(0, 10000, 600000); remote.release(); advance(300)
        assertEquals(listOf(10000L), seeks)
    }

    @Test fun activityCoalescesMediaKeysWithoutChangingPauseState() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withPlayer { activity, fake, _ ->
            repeat(12) {
                key(activity, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.ACTION_DOWN)
                key(activity, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.ACTION_UP)
                advance(100)
            }
            assertTrue(fake.seeks.isEmpty()); advance(200)
            assertEquals(listOf(150000L), fake.seeks)
            assertEquals(0, fake.playbackStateChanges)
        }
    }

    @Test fun activityCancelsPendingSeekWhenBackgrounded() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withPlayer { activity, fake, background ->
            key(activity, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.ACTION_DOWN)
            key(activity, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.ACTION_UP)
            background(); advance(1000)
            assertTrue(fake.seeks.isEmpty())
        }
    }

    @Test fun screenButtonsCoalesceAndBackCancelsSelection() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        withPlayer { activity, fake, _ ->
            repeat(3) { activity.findViewById<View>(androidx.media3.ui.R.id.exo_ffwd).performClick(); advance(100) }
            advance(200); assertEquals(listOf(60000L), fake.seeks)
            activity.findViewById<View>(androidx.media3.ui.R.id.exo_rew).performClick()
            key(activity, KeyEvent.KEYCODE_BACK, KeyEvent.ACTION_DOWN)
            key(activity, KeyEvent.KEYCODE_BACK, KeyEvent.ACTION_UP)
            advance(500); assertEquals(listOf(60000L), fake.seeks)
        }
    }

    private fun key(activity: PlayerActivity, code: Int, action: Int) {
        activity.dispatchKeyEvent(KeyEvent(action, code))
    }

    private fun withPlayer(test: (PlayerActivity, FakePlayer, () -> Unit) -> Unit) {
        val controller = Robolectric.buildActivity(UiOnlyPlayerActivity::class.java,
            Intent(RuntimeEnvironment.getApplication(), UiOnlyPlayerActivity::class.java)
                .putExtra("torrentId", "a".repeat(40)))
            .setup().windowFocusChanged(true)
        val fake = FakePlayer()
        PlayerActivity::class.java.getDeclaredField("player").apply { isAccessible = true }.set(controller.get(), fake.player)
        var paused = false
        try { test(controller.get(), fake) { controller.pause(); paused = true } }
        finally {
            if (!paused) controller.pause()
            controller.stop().destroy()
        }
    }

    // Exercise Activity key/lifecycle wiring without a decoder or network.
    private class FakePlayer {
        val seeks = mutableListOf<Long>()
        var position = 30000L
        var playbackStateChanges = 0
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, args ->
            when (method.name) {
                "getCurrentPosition" -> position
                "getDuration" -> 600000L
                "getPlaybackState" -> Player.STATE_READY
                "seekTo" -> { position = args!!.last() as Long; seeks.add(position); null }
                "setPlayWhenReady", "play", "pause" -> { playbackStateChanges++; null }
                else -> when (method.returnType) {
                    java.lang.Boolean.TYPE -> false
                    java.lang.Integer.TYPE -> 0
                    java.lang.Long.TYPE -> 0L
                    else -> null
                }
            }
        } as ExoPlayer
    }
}
