package local.freescene.freescene

import org.json.JSONObject

/** Match explicit episode names only. Ambiguous files retain the manual chooser. */
internal object TorrentEpisode {
    private val numbered = Regex("(?i)(?<![a-z0-9])s(\\d{1,3})[ ._-]*e(\\d{1,4})(?![0-9])")
    private val alternate = Regex("(?i)(?<![a-z0-9])(\\d{1,3})x(\\d{1,4})(?![0-9])")
    private val continuation = Regex("(?i)^(?:[ ._-]*[ex][0-9]|[ ._]*-[ ._]*[0-9])")
    fun probeIndex(videos: List<JSONObject>, season: Int, episode: Int): Int? =
        if (episode >= 0) index(videos, season, episode) else videos.firstOrNull()?.getInt("index")
    fun index(files: List<JSONObject>, season: Int, episode: Int): Int? {
        if (episode !in 0..9999 || season !in -1..999) return null
        return files.filter { file ->
            val name = file.optString("name")
            val match = (numbered.findAll(name) + alternate.findAll(name)).singleOrNull()
            match != null && !continuation.containsMatchIn(name.substring(match.range.last + 1)) &&
                (season < 0 || match.groupValues[1].toInt() == season) &&
                match.groupValues[2].toInt() == episode
        }.singleOrNull()?.getInt("index")
    }
}
