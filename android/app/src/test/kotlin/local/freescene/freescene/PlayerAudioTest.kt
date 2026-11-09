package local.freescene.freescene

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import com.google.common.collect.ImmutableList
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlayerAudioTest {
    @Test fun audioExtensionIsAvailableAfterPlatformRendererAndVideoRemainsPlatformDecoded() {
        val renderers = PlayerAudio.renderers(RuntimeEnvironment.getApplication()).createRenderers(
            android.os.Handler(android.os.Looper.getMainLooper()),
            object : androidx.media3.exoplayer.video.VideoRendererEventListener {},
            object : androidx.media3.exoplayer.audio.AudioRendererEventListener {},
            object : androidx.media3.exoplayer.text.TextOutput {
                override fun onCues(cueGroup: androidx.media3.common.text.CueGroup) {}
            },
            object : androidx.media3.exoplayer.metadata.MetadataOutput {
                override fun onMetadata(metadata: androidx.media3.common.Metadata) {}
            })
        val names = renderers.map { it.javaClass.name }
        val platform = names.indexOf("androidx.media3.exoplayer.audio.MediaCodecAudioRenderer")
        val software = names.indexOf("androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer")
        assertTrue("$names", platform >= 0 && software > platform)
        assertEquals(1, renderers.count { it.trackType == C.TRACK_TYPE_VIDEO })
        assertTrue(names.contains("androidx.media3.exoplayer.video.MediaCodecVideoRenderer"))
    }
    private fun group(mime: String, support: Int, selected: Boolean) = Tracks.Group(
        TrackGroup(Format.Builder().setSampleMimeType(mime).setChannelCount(6).setSampleRate(48000).build()),
        false, intArrayOf(support), booleanArrayOf(selected))

    @Test fun unsupportedDolbyAndDtsAreExplainedInsteadOfSilentPlayback() {
        for (mime in listOf("audio/ac3", "audio/eac3", "audio/vnd.dts")) {
            val tracks = Tracks(ImmutableList.of(group(mime, C.FORMAT_UNSUPPORTED_SUBTYPE, false)))
            assertTrue(PlayerAudio.unsupported(tracks))
            assertEquals("Формат звука не поддерживается. Выберите другой источник.", PlayerAudio.warning(tracks, true))
            assertEquals("Audio format is not supported. Choose another source.", PlayerAudio.warning(tracks, false))
        }
    }
    @Test fun softwareSupportedAudioDoesNotShowWarning() {
        assertNull(PlayerAudio.warning(Tracks(ImmutableList.of(group("audio/eac3", C.FORMAT_HANDLED, true))), true))
    }
    @Test fun oneSupportedTrackIsEnoughEvenIfAnotherIsUnsupported() {
        val tracks = Tracks(ImmutableList.of(group("audio/ac3", C.FORMAT_UNSUPPORTED_SUBTYPE, false),
            group("audio/mp4a-latm", C.FORMAT_HANDLED, true)))
        assertFalse(PlayerAudio.unsupported(tracks))
    }
    @Test fun deliberatelyDisabledSupportedAudioIsNotReportedAsUnsupported() {
        assertFalse(PlayerAudio.unsupported(Tracks(ImmutableList.of(group("audio/ac3", C.FORMAT_HANDLED, false)))))
    }
    @Test fun silentVideoAndUnpreparedPlayerDoNotShowWarnings() {
        assertFalse(PlayerAudio.unsupported(Tracks.EMPTY))
        assertFalse(PlayerAudio.unsupported(Tracks(ImmutableList.of(group("video/avc", C.FORMAT_HANDLED, true)))))
    }
}
