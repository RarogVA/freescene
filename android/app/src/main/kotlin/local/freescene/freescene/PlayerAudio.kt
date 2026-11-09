package local.freescene.freescene

import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.DefaultRenderersFactory

/** Keep platform decoders first; the audio-only extension handles missing Dolby/DTS codecs. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object PlayerAudio {
    fun renderers(context: Context) = DefaultRenderersFactory(context)
        .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        .setEnableDecoderFallback(true)

    fun unsupported(tracks: Tracks): Boolean = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO } &&
        !tracks.isTypeSupported(C.TRACK_TYPE_AUDIO)

    fun warning(tracks: Tracks, russian: Boolean): String? = if (!unsupported(tracks)) null else
        if (russian) "Формат звука не поддерживается. Выберите другой источник."
        else "Audio format is not supported. Choose another source."
}
