package local.freescene.freescene

import androidx.media3.common.*
import com.google.common.collect.ImmutableList
import java.lang.reflect.Proxy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class AudioPreferenceTest {
    private fun group(id: String, language: String?, label: String? = null, selected: Boolean = false, supported: Boolean = true) =
        Tracks.Group(TrackGroup(id, Format.Builder().setSampleMimeType("audio/aac").setLanguage(language).setLabel(label).build()),
            false, intArrayOf(if (supported) C.FORMAT_HANDLED else C.FORMAT_UNSUPPORTED_SUBTYPE), booleanArrayOf(selected))
    @Test fun languageAndRoleRankingNeverInventsUnknownLanguage() {
        for (language in listOf("en", "eng", "en-US", "en_GB")) assertEquals(200, AudioPreference.score(language, null))
        assertEquals(100, AudioPreference.score("ja", "Original"))
        assertEquals(0, AudioPreference.score(null, "Stereo"))
        assertEquals(0, AudioPreference.score("ru", "English"))
        assertEquals(200, AudioPreference.score("und", "English"))
        assertTrue(AudioPreference.score("en", "Commentary") < AudioPreference.score("en", null))
    }
    @Test fun selectsPlayableEnglishThenOriginalAndRespectsManualOverride() {
        val russian = group("ru", "ru", selected = true)
        val original = group("ja", "ja", "Original")
        val english = group("en", "en")
        var tracks = Tracks(ImmutableList.of(russian))
        var parameters = TrackSelectionParameters.DEFAULT
        var writes = 0
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, args ->
            when(method.name) {
                "getCurrentTracks" -> tracks
                "getTrackSelectionParameters" -> parameters
                "setTrackSelectionParameters" -> { parameters = args!![0] as TrackSelectionParameters; writes++; null }
                else -> throw AssertionError(method.name)
            }
        } as Player
        val preference = AudioPreference(true)
        preference.apply(player);assertEquals(0,writes)
        tracks = Tracks(ImmutableList.of(russian, original, group("bad", "en", supported = false)))
        preference.apply(player);assertTrue(parameters.overrides.containsKey(original.mediaTrackGroup))
        tracks = Tracks(ImmutableList.of(russian, original, english))
        preference.apply(player);assertTrue(parameters.overrides.containsKey(english.mediaTrackGroup))
        preference.manual = true
        val before = writes;preference.apply(player);assertEquals(before,writes)
        AudioPreference(false).apply(player);assertEquals(before,writes)
    }
    @Test fun appLanguageIsStoredIndependentlyOfSystemLanguage() {
        val context=RuntimeEnvironment.getApplication()
        PlaybackLanguage.configure(context,true);assertTrue(PlaybackLanguage.english(context))
        PlaybackLanguage.configure(context,false);assertFalse(PlaybackLanguage.english(context))
    }
}
