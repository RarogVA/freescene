package local.freescene.freescene

import android.content.res.Resources
import androidx.media3.common.Format
import androidx.media3.ui.DefaultTrackNameProvider
import androidx.media3.ui.TrackNameProvider

/** Keep container titles (e.g. dubbing studios) alongside Media3's localized details. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class PlayerTrackNames(resources: Resources) : TrackNameProvider {
    private val fallback = DefaultTrackNameProvider(resources)
    override fun getTrackName(format: Format): String {
        val label = format.label?.replace(Regex("[\\p{Cntrl}\\s]+"), " ")?.trim()?.take(160).orEmpty()
        val details = fallback.getTrackName(format).replace(Regex("[\\p{Cntrl}\\s]+"), " ").trim()
        return if (label.isEmpty() || details.startsWith(label, ignoreCase = true)) details
            else "$label · $details"
    }
}
