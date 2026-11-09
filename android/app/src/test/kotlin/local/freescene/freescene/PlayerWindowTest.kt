package local.freescene.freescene

import android.content.Intent
import android.view.KeyEvent
import android.view.View
import android.view.ContextThemeWrapper
import android.os.Looper
import android.os.Bundle
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.ViewGroup
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import org.robolectric.shadows.ShadowAlertDialog
import java.time.Duration
import org.robolectric.Shadows.shadowOf
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

class UiOnlyPlayerActivity : PlayerActivity() {
    var starts = 0
    override fun startPlayer() { starts++ /* Device decoder/network is tested on hardware. */ }
}

/** Real Android activity lifecycle, view hierarchy and key dispatch; no decoder/network. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlayerWindowTest {
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    @Test fun scaleMenuChangesVideoWithoutRestartAndSurvivesRecreation() {
        val controller = controller(); val activity = controller.get()
        fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
            (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
        val player = descendants(activity.window.decorView).filterIsInstance<PlayerView>().single()
        val scale = activity.window.decorView.findViewWithTag<View>("player-scale")
        val close = activity.window.decorView.findViewWithTag<PlayerCloseButton>("player-close")
        val root = scale.parent as View
        assertEquals("Scale is at the opposite edge from Close", close.left, root.width - scale.right)
        assertEquals(Color.BLACK, (player.background as ColorDrawable).color)
        assertEquals(AspectRatioFrameLayout.RESIZE_MODE_FIT, player.resizeMode)
        for ((selection, expected) in listOf(1 to AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
                2 to AspectRatioFrameLayout.RESIZE_MODE_FILL, 0 to AspectRatioFrameLayout.RESIZE_MODE_FIT)) {
            scale.requestFocus()
            scale.performClick()
            val dialog = ShadowAlertDialog.getLatestAlertDialog()
            assertEquals(3, dialog.listView.adapter.count)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
            assertTrue(scale.isShown)
            dialog.listView.performItemClick(null, selection, selection.toLong())
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(expected, player.resizeMode)
            if (TvWindow.isTv(activity)) assertTrue(scale.hasFocus())
            assertFalse(activity.isFinishing)
        }
        scale.performClick()
        ShadowAlertDialog.getLatestAlertDialog().listView.performItemClick(null, 2, 2)
        val saved = Bundle(); controller.saveInstanceState(saved).pause().stop().destroy()
        val restored = Robolectric.buildActivity(UiOnlyPlayerActivity::class.java, activity.intent)
            .create(saved).start().resume().visible()
        val restoredView = descendants(restored.get().window.decorView).filterIsInstance<PlayerView>().single()
        assertEquals(AspectRatioFrameLayout.RESIZE_MODE_FILL, restoredView.resizeMode)
        restored.pause().stop().destroy()
    }
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    @Test fun titleAndButtonsFollowNativeControllerVisibility() {
        val controller = controller(); val activity = controller.get()
        val title = activity.window.decorView.findViewWithTag<PlayerTitleView>("player-title")
        val scale = activity.window.decorView.findViewWithTag<View>("player-scale")
        val root = title.parent as ViewGroup
        val player = (0 until root.childCount).map { root.getChildAt(it) }.filterIsInstance<PlayerView>().single()
        val close = activity.window.decorView.findViewWithTag<PlayerCloseButton>("player-close")
        player.hideController()
        assertFalse(title.isShown)
        assertFalse(close.isShown)
        assertFalse(scale.isShown)
        player.showController()
        assertTrue(title.isShown)
        assertTrue(close.isShown)
        assertTrue(scale.isShown)
        controller.pause().stop().destroy()
    }
    @Test fun tvCloseHidesAfterInactivityAndFirstOkOnlyRestoresIt() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        val controller = controller()
        val activity = controller.get()
        val close = activity.window.decorView.findViewWithTag<PlayerCloseButton>("player-close")
        val title = activity.window.decorView.findViewWithTag<PlayerTitleView>("player-title")
        assertEquals("Fixture movie", title.text.toString())
        assertFalse(title.isFocusable)
        // Measure from the last remote event, after Android's initial layout.
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_UP))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(3999))
        assertEquals(View.VISIBLE, close.visibility)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1))
        assertEquals(View.INVISIBLE, close.visibility)
        assertEquals(View.INVISIBLE, title.visibility)
        assertNotNull(activity.window.decorView.findFocus())
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER))
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_CENTER))
        assertEquals(View.VISIBLE, close.visibility)
        assertEquals(View.VISIBLE, title.visibility)
        assertTrue(close.hasFocus())
        assertFalse(activity.isFinishing)
        controller.pause().stop().destroy()
    }
    @Test fun extensionlessCdnUrlStillUsesTheHlsDecoder() {
        val media = PlaybackPolicy.mediaItem("https://cdn.test/stream/720?token=fixture", "application/x-mpegURL")
        assertEquals("application/x-mpegURL", media.localConfiguration!!.mimeType)
    }

    private fun controller() = Robolectric.buildActivity(UiOnlyPlayerActivity::class.java,
        Intent(RuntimeEnvironment.getApplication(), UiOnlyPlayerActivity::class.java)
            .putExtra("url", "https://127.0.0.1/fixture.m3u8")
            .putExtra("title", "Fixture movie")).setup().windowFocusChanged(true)

    @Test fun closeControlHasRemoteFocusOnTvAndClosesPlayer() {
        val controller = controller()
        val activity = controller.get()
        // ShadowActivity.getCurrentFocus() is a manually populated stub in
        // Robolectric; inspect the actual Android view tree instead.
        val focused = activity.window.decorView.findViewWithTag<PlayerCloseButton>("player-close")
        if (TvWindow.isTv(activity)) assertTrue(focused.hasFocus())
        assertTrue("Actual focus: $focused", focused is PlayerCloseButton)
        assertTrue((focused as PlayerCloseButton).contentDescription in listOf("Close", "Закрыть"))
        assertEquals(focused.diameter, focused.layoutParams.width)
        assertEquals(focused.diameter, focused.layoutParams.height)
        assertNotNull(focused.drawable)
        assertTrue(focused.performClick())
        assertTrue(activity.isFinishing)
        controller.destroy()
    }
    @Test fun phoneScaleAndCloseRespondToTheFirstTouch() {
        assumeTrue(BuildConfig.FLAVOR == "mobile")
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().setInTouchMode(true)
        val controller = controller(); val activity = controller.get()
        val close = activity.window.decorView.findViewWithTag<PlayerCloseButton>("player-close")
        val scale = activity.window.decorView.findViewWithTag<View>("player-scale")
        assertTrue(close.isInTouchMode)
        assertFalse(close.hasFocus())
        assertFalse(scale.hasFocus())
        tapPlayerControl(activity, scale)
        val dialog = ShadowAlertDialog.getLatestAlertDialog()
        assertNotNull("The first tap must open the scale menu", dialog)
        assertTrue(dialog.isShowing)
        dialog.dismiss()
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(scale.hasFocus())
        activity.onWindowFocusChanged(true)
        assertFalse(close.hasFocus())
        tapPlayerControl(activity, close)
        assertTrue("The first tap must close the player", activity.isFinishing)
        controller.pause().stop().destroy()
    }
    @Test fun tvBackHidesControlsThenExitsAndMobileBackExitsImmediately() {
        val controller = controller()
        val activity = controller.get()
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)))
        if (BuildConfig.FLAVOR == "tv") {
            assertFalse(activity.isFinishing)
            assertEquals(1, activity.starts)
            assertFalse(activity.window.decorView.findViewWithTag<PlayerTitleView>("player-title").isShown)
            activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
            activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
        }
        assertTrue(activity.isFinishing)
        controller.destroy()
    }
    @Test fun heldBackCannotBothHideControlsAndClosePlayerEvenIfIdleTimerExpires() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        val controller = controller(); val activity = controller.get()
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        activity.dispatchKeyEvent(KeyEvent(0, 10, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK, 1))
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
        assertFalse(activity.isFinishing)
        assertEquals(1, activity.starts)
        controller.pause().stop().destroy()
    }
    @Test fun backFromAutoHiddenControlsCanStillExitAndCanceledBackDoesNotExit() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        val controller = controller(); val activity = controller.get()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
        activity.dispatchKeyEvent(KeyEvent.changeFlags(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK), KeyEvent.FLAG_CANCELED))
        assertFalse(activity.isFinishing)
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
        activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
        assertTrue(activity.isFinishing)
        controller.destroy()
    }
    @Suppress("DEPRECATION")
    @Test fun playbackHidesBothSystemBarsAndRestoresAfterWindowFocus() {
        val controller = controller()
        val activity = controller.get()
        activity.onWindowFocusChanged(true)
        val flags = activity.window.decorView.systemUiVisibility
        assertTrue(flags and View.SYSTEM_UI_FLAG_FULLSCREEN != 0)
        assertTrue(flags and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION != 0)
        assertTrue(flags and View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY != 0)
        activity.window.decorView.systemUiVisibility = 0
        activity.onWindowFocusChanged(true)
        assertEquals(flags, activity.window.decorView.systemUiVisibility)
        controller.destroy()
    }
    @Test fun tvLaunchAndNormalThemesHideWindowChromeInDayAndNight() {
        assumeTrue(BuildConfig.FLAVOR == "tv")
        for (qualifiers in listOf("notnight", "night")) {
            RuntimeEnvironment.setQualifiers(qualifiers)
            for (style in listOf(R.style.LaunchTheme, R.style.NormalTheme)) {
                val theme = ContextThemeWrapper(RuntimeEnvironment.getApplication(), style)
                val attrs = theme.obtainStyledAttributes(intArrayOf(android.R.attr.windowFullscreen,
                    android.R.attr.windowNoTitle))
                try {
                    assertTrue("$qualifiers fullscreen", attrs.getBoolean(0, false))
                    assertTrue("$qualifiers no title", attrs.getBoolean(1, false))
                } finally { attrs.recycle() }
            }
        }
    }
    @Test fun unsafeRestoredPlayerIntentExitsWithoutInflatingPlayer() {
        val controller = Robolectric.buildActivity(PlayerActivity::class.java,
            Intent(RuntimeEnvironment.getApplication(), PlayerActivity::class.java)
                .putExtra("url", "file:///private/fixture")).create()
        assertTrue(controller.get().isFinishing)
        controller.destroy()
    }
}
