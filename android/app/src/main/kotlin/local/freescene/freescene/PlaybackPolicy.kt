package local.freescene.freescene

import java.net.URI
import local.freescene.provider_host.ProviderHost
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes

/** Shared by the channel boundary and player activity, including restored intents. */
object PlaybackPolicy {
    fun referrer(media: String?, value: String?): String? = ProviderHost.web?.referrer(media, value)

    fun mediaItem(url: String, mimeType: String?): MediaItem {
        require(allowed(url))
        return MediaItem.Builder().setUri(url).apply {
            if (mimeType == MimeTypes.APPLICATION_M3U8) setMimeType(mimeType)
        }.build()
    }

    fun allowed(url: String?): Boolean = try {
        val uri = URI(url ?: "")
        url != null && url.length <= 8192 && uri.scheme == "https" &&
            !uri.host.isNullOrEmpty() && uri.rawUserInfo == null &&
            (uri.port == -1 || uri.port == 443)
    } catch (_: Exception) { false }

    fun bufferBytes(lowRam: Boolean) = (if (lowRam) 24 else 48) * 1024 * 1024
    fun seek(position: Long, delta: Long, duration: Long): Long =
        (position + delta).coerceAtLeast(0).let { if (duration >= 0) it.coerceAtMost(duration) else it }
}
