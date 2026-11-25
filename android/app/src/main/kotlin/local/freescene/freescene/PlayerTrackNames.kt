package local.freescene.freescene

import android.content.res.Resources
import androidx.media3.common.Format
import androidx.media3.common.util.Util
import java.util.Locale
import androidx.media3.ui.DefaultTrackNameProvider
import androidx.media3.ui.TrackNameProvider

/** Keep container titles (e.g. dubbing studios) alongside Media3's localized details. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class PlayerTrackNames(private val resources: Resources) : TrackNameProvider {
    private val fallback = DefaultTrackNameProvider(resources)
    override fun getTrackName(format: Format): String {
        val label = format.label?.replace(Regex("[\\p{Cntrl}\\s]+"), " ")?.trim()?.take(160).orEmpty()
        val details = localizedTrackName(format).replace(Regex("[\\p{Cntrl}\\s]+"), " ").trim()
        return if (label.isEmpty() || details.startsWith(label, ignoreCase = true)) details
            else "$label · $details"
    }

    private fun localizedTrackName(format: Format): String {
        val name = fallback.getTrackName(format)
        val language = format.language?.takeUnless { it.isBlank() || it == "und" } ?: return name
        // Media3 formats channel layout and roles using Resources, but uses the
        // device display locale for the language prefix.
        val tag = Locale.forLanguageTag(language)
        val deviceName = tag.getDisplayName(Util.getDefaultDisplayLocale())
        if (deviceName.isEmpty() || !name.startsWith(deviceName, ignoreCase = true)) return name
        val locale = resources.configuration.locales[0]
        val localizedName = tag.getDisplayName(locale).replaceFirstChar { it.titlecase(locale) }
        return localizedName + name.substring(deviceName.length)
    }

    fun audioTrackName(format: Format, number: Int): String {
        val name = getTrackName(format)
        val language = format.language?.trim()?.lowercase().orEmpty()
        val label = format.label?.replace(Regex("[\\p{Cntrl}\\s]+"), " ")?.trim().orEmpty()
        if (language.isNotEmpty() && language.substringBefore('-') != "und") return name
        // Labels may themselves contain the only available language or dubbing name.
        if (label.isNotEmpty() && !label.equals("Stereo", true) && !label.equals("Стерео", true)) return name
        val ru = resources.configuration.locales[0].language == "ru"
        return if (ru) "Дорожка $number · Язык не указан · $name"
            else "Track $number · Language unspecified · $name"
    }
}
