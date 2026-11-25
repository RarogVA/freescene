package local.freescene.freescene

import android.content.Context
import android.content.res.Configuration
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import java.util.Locale

/** Shared by the player UI and its automatic audio selection. */
object PlaybackLanguage {
    fun configure(context: Context, english: Boolean) {
        context.getSharedPreferences("playback-language", Context.MODE_PRIVATE)
            .edit().putBoolean("english", english).apply()
    }
    fun configuration(context: Context) = Configuration().apply {
        setLocale(if (english(context)) Locale.ENGLISH else Locale.forLanguageTag("ru"))
    }

    fun english(context: Context) = context.getSharedPreferences("playback-language", Context.MODE_PRIVATE)
        .getBoolean("english", false)
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class AudioPreference(private val english: Boolean) {
    var manual = false
    fun apply(player: Player) {
        if (!english || manual) return
        val candidates = player.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }.flatMap { group ->
            (0 until group.length).filter { group.isTrackSupported(it) }.map { index ->
                val format = group.getTrackFormat(index)
                Triple(group, index, score(format.language, format.label, format.roleFlags))
            }
        }.filter { it.third > 0 }
        val best = candidates.maxWithOrNull(compareBy<Triple<androidx.media3.common.Tracks.Group, Int, Int>> { it.third }
            .thenBy { if (it.first.isTrackSelected(it.second)) 1 else 0 }) ?: return
        if (best.first.isTrackSelected(best.second)) return
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setOverrideForType(TrackSelectionOverride(best.first.mediaTrackGroup, best.second)).build()
    }

    companion object {
        private val englishName = Regex("(^|[^\\p{L}])(english|английский|английская|eng|en)([^\\p{L}]|$)", RegexOption.IGNORE_CASE)
        private val originalName = Regex("(^|[^\\p{L}])(original|оригинал|оригинальная)([^\\p{L}]|$)", RegexOption.IGNORE_CASE)
        private val commentaryName = Regex("commentary|комментар|audio description|тифло", RegexOption.IGNORE_CASE)
        fun score(language: String?, label: String?, roles: Int = 0): Int {
            val base = language.orEmpty().lowercase(Locale.ROOT).replace('_', '-').substringBefore('-')
            val name = label.orEmpty()
            val known = base !in setOf("", "und", "unk", "zxx")
            val rank = if (base == "en" || base == "eng" || (!known && englishName.containsMatchIn(name))) 200
                else if (originalName.containsMatchIn(name)) 100 else 0
            if (rank == 0) return 0
            return rank - if (roles and (C.ROLE_FLAG_COMMENTARY or C.ROLE_FLAG_DESCRIBES_VIDEO) != 0 || commentaryName.containsMatchIn(name)) 10 else 0
        }
    }
}
