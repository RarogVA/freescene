package local.freescene.freescene

import android.app.AlertDialog
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.ui.DefaultTrackNameProvider
import androidx.media3.ui.PlayerView
import com.google.common.collect.ImmutableList
import java.lang.reflect.Proxy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlertDialog

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlayerSettingsTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private fun audio(label: String? = null) = Format.Builder().setSampleMimeType("audio/ac3")
        .setLanguage("ru").setChannelCount(6).setLabel(label).build()
    private fun group(id: String, format: Format, selected: Boolean, support: Int = C.FORMAT_HANDLED) =
        Tracks.Group(TrackGroup(id, format), false, intArrayOf(support), booleanArrayOf(selected))
    private fun dialog() = ShadowAlertDialog.getLatestAlertDialog()
    private fun click(index: Int) { shadowOf(dialog()).clickOnItem(index) }

    @Test fun dubbingLabelsDistinguishOtherwiseIdenticalAudioAndRetainLocalizedDetails() {
        val provider = PlayerTrackNames(context.resources)
        val fallback = DefaultTrackNameProvider(context.resources).getTrackName(audio())
        assertEquals("LostFilm · $fallback", provider.getTrackName(audio("LostFilm")))
        assertEquals("AlexFilm · $fallback", provider.getTrackName(audio("AlexFilm")))
    }
    @Test fun absentBlankAndDuplicateLabelsKeepMedia3Fallback() {
        val provider = PlayerTrackNames(context.resources)
        val format = audio()
        val fallback = DefaultTrackNameProvider(context.resources).getTrackName(format)
        for (label in listOf(null, "", " \n\t ", fallback)) assertEquals(fallback, provider.getTrackName(audio(label)))
        val noLanguage = audio("LostFilm").buildUpon().setLanguage(null).build()
        assertEquals(DefaultTrackNameProvider(context.resources).getTrackName(noLanguage), provider.getTrackName(noLanguage))
        assertTrue(provider.getTrackName(audio(" LostFilm\n\t HD ")).startsWith("LostFilm HD · "))
    }

    private class Fixture {
        var tracks = Tracks(ImmutableList.of(
            Tracks.Group(TrackGroup("first", Format.Builder().setSampleMimeType("audio/ac3").setLanguage("ru").setChannelCount(6).setLabel("LostFilm").build()), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)),
            Tracks.Group(TrackGroup("second", Format.Builder().setSampleMimeType("audio/ac3").setLanguage("ru").setChannelCount(6).setLabel("AlexFilm").build()), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))))
        var selection = TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT
        var speed = 1f
        var writes = 0
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, args ->
            when (method.name) {
                "isCommandAvailable" -> true
                "getCurrentTracks" -> tracks
                "getTrackSelectionParameters" -> selection
                "setTrackSelectionParameters" -> { selection = args!![0] as TrackSelectionParameters; writes++; null }
                "getPlaybackParameters" -> PlaybackParameters(speed)
                "setPlaybackSpeed" -> { speed = args!![0] as Float; null }
                else -> throw AssertionError("Unexpected player call ${method.name}")
            }
        } as Player
    }
    @Test fun settingsButtonOpensNamedAudioAndSelectionPreservesVideoAndSubtitleOverrides() {
        val f = Fixture()
        val video = TrackGroup("video", Format.Builder().setSampleMimeType("video/avc").build())
        val text = TrackGroup("subtitles", Format.Builder().setSampleMimeType("text/vtt").build())
        f.selection = f.selection.buildUpon().addOverride(TrackSelectionOverride(video, 0))
            .addOverride(TrackSelectionOverride(text, 0)).build()
        var controlsPaused = false
        val settings = PlayerSettings(context, opened = { controlsPaused = true },
            dismissed = { controlsPaused = false }) { f.player }
        val view = PlayerView(context)
        settings.bind(view)
        if (TvWindow.isTv(context)) {
            assertNull(view.findViewById<View>(androidx.media3.ui.R.id.exo_settings))
            assertTrue(view.findViewById<View>(androidx.media3.ui.R.id.exo_audio_track).performClick())
        } else {
            assertTrue(view.findViewById<View>(androidx.media3.ui.R.id.exo_settings).performClick())
            click(0)
        }
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue("Moving into Audio keeps the controls timer paused", controlsPaused)
        val rows = dialog().listView.adapter
        assertTrue(rows.getItem(1).toString().contains("LostFilm"))
        assertTrue(rows.getItem(2).toString().contains("AlexFilm"))
        click(2)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertFalse(controlsPaused)
        assertEquals(1, f.writes)
        assertTrue(f.selection.overrides.containsKey(f.tracks.groups[1].mediaTrackGroup))
        assertTrue(f.selection.overrides.containsKey(video))
        assertTrue(f.selection.overrides.containsKey(text))
        assertFalse(f.selection.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO))
        settings.dismiss()
    }
    @Test fun autoClearsOnlyAudioOverrideAndCancellationDoesNotChangePlayer() {
        val f = Fixture()
        val text = TrackGroup("subtitles", Format.Builder().setSampleMimeType("text/vtt").build())
        f.selection = f.selection.buildUpon().addOverride(TrackSelectionOverride(f.tracks.groups[0].mediaTrackGroup, 0))
            .addOverride(TrackSelectionOverride(text, 0)).build()
        val settings = PlayerSettings(context) { f.player }
        settings.showAudio()
        dialog().getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        assertEquals(0, f.writes)
        settings.showAudio(); click(0)
        assertEquals(setOf(text), f.selection.overrides.keys)
    }
    @Test fun unsupportedAndStaleTracksAreNotSelectedAndOldPlayerIsNeverModified() {
        val f = Fixture()
        f.tracks = Tracks(ImmutableList.of(f.tracks.groups[0], group("unsupported", audio("DTS"), false, C.FORMAT_UNSUPPORTED_SUBTYPE)))
        var current: Player? = f.player
        val settings = PlayerSettings(context) { current }
        settings.showAudio()
        assertEquals(2, dialog().listView.adapter.count)
        f.tracks = Tracks.EMPTY
        click(1)
        assertEquals(0, f.writes)
        settings.showAudio(); current = null; click(0)
        assertEquals(0, f.writes)
    }
    @Test fun mobileMenuGroupsAudioSpeedSubtitlesAndScale() {
        org.junit.Assume.assumeTrue(BuildConfig.FLAVOR == "mobile")
        val f = Fixture(); var scaled = false
        val settings = PlayerSettings(context, scaling = { scaled = true }) { f.player }
        settings.show()
        assertEquals(4, dialog().listView.adapter.count)
        click(3); assertTrue(scaled)
        settings.showSubtitles(); click(0)
        assertTrue(f.selection.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        settings.showSubtitles(); click(1)
        assertFalse(f.selection.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun tvAudioAndSpeedAreIndependentDirectActions() {
        org.junit.Assume.assumeTrue(BuildConfig.FLAVOR == "tv")
        val f = Fixture(); val settings = PlayerSettings(context) { f.player }
        val view = PlayerView(context); settings.bind(view)
        assertNull(view.findViewById<View>(androidx.media3.ui.R.id.exo_settings))
        view.findViewById<View>(androidx.media3.ui.R.id.exo_playback_speed).performClick()
        click(5); assertEquals(1.5f, f.speed)
        view.findViewById<View>(androidx.media3.ui.R.id.exo_audio_track).performClick()
        assertTrue(dialog().listView.adapter.getItem(1).toString().contains("LostFilm"))
        settings.dismiss()
    }
    @Test fun subtitleMenuKeepsTheSelectedTrackWithinTheSameGroup() {
        val f = Fixture()
        val text = TrackGroup("subtitles",
            Format.Builder().setSampleMimeType("text/vtt").setLanguage("en").build(),
            Format.Builder().setSampleMimeType("text/vtt").setLanguage("ru").build())
        f.tracks = Tracks(ImmutableList.of(Tracks.Group(text, false,
            intArrayOf(C.FORMAT_HANDLED, C.FORMAT_HANDLED), booleanArrayOf(false, true))))
        f.selection = f.selection.buildUpon().addOverride(TrackSelectionOverride(text, 1)).build()
        val settings = PlayerSettings(context) { f.player }
        settings.showSubtitles()
        assertEquals(3, dialog().listView.checkedItemPosition)
        click(2)
        assertEquals(listOf(0), f.selection.overrides[text]?.trackIndices)
        settings.showSubtitles()
        assertEquals(2, dialog().listView.checkedItemPosition)
        settings.dismiss()
    }
    @Test fun tvSubtitleButtonOpensTheSharedDialogAndRestoresFocus() {
        org.junit.Assume.assumeTrue(BuildConfig.FLAVOR == "tv")
        val activity = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup()
        val f = Fixture()
        val text = group("subtitles", Format.Builder().setSampleMimeType("text/vtt").setLanguage("en").build(), true)
        f.tracks = Tracks(ImmutableList.of(text))
        val view = PlayerView(activity.get()); view.setShowSubtitleButton(true)
        activity.get().setContentView(view); activity.visible()
        val settings = PlayerSettings(activity.get()) { f.player }; settings.bind(view)
        val button = view.findViewById<View>(androidx.media3.ui.R.id.exo_subtitle)
        button.isEnabled = true; button.visibility = View.VISIBLE
        button.requestFocus(); button.performClick()
        assertEquals(3, dialog().listView.adapter.count)
        click(2)
        assertEquals(listOf(0), f.selection.overrides[text.mediaTrackGroup]?.trackIndices)
        assertTrue(button.hasFocus())
        button.performClick()
        assertEquals(2, dialog().listView.checkedItemPosition)
        dialog().cancel()
        assertTrue(button.hasFocus())
        assertEquals(1, f.writes)
        settings.dismiss(); activity.pause().stop().destroy()
    }
    @Test fun playbackSpeedStillWorksAndDismissClosesOpenDialog() {
        val f = Fixture()
        val settings = PlayerSettings(context) { f.player }
        settings.showSpeed(); click(5)
        assertEquals(1.5f, f.speed)
        settings.showAudio(); val opened = dialog()
        settings.dismiss()
        assertFalse(opened.isShowing)
        assertEquals(0, f.writes)
    }
}
