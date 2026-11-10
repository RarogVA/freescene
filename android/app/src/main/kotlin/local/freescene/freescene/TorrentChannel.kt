package local.freescene.freescene

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

class TorrentChannel(private val activity: Activity) {
    private var picker: MethodChannel.Result? = null
    private fun reply(result: MethodChannel.Result): (Result<JSONObject>) -> Unit = { value ->
        value.onSuccess { result.success(TorrentEngine.map(it)) }
            .onFailure { result.error("torrent", it.message ?: "Ошибка загрузки", null) }
    }
    fun call(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (TvWindow.isTv(activity) && call.method != "torrentOpen") {
                result.error("playback_only", "Android TV supports torrent playback only", null)
                return
            }
            when (call.method) {
                "torrentOpen" -> {
                    val origin = call.argument<Map<String, String>>("origin") ?: mapOf("local" to "magnet")
                    TorrentEngine.add(activity, call.argument<ByteArray>("bytes"), call.argument<String>("magnet"), JSONObject(origin)) { value ->
                        value.onSuccess { task ->
                            val id = task.getString("id")
                            if (activity.isFinishing || activity.isDestroyed) {
                                TorrentEngine.submit(activity, JSONObject().put("method", "closeStream").put("id", id))
                                result.success(null)
                            } else try {
                                PlayerColors.configure(activity, call.argument<Boolean>("playerDark") != false)
                                activity.startActivity(Intent(activity, PlayerActivity::class.java).putExtra("torrentId", id)
                                    .putExtra("title", call.argument<String>("title"))
                                .putExtra("watchedSource", call.argument<String>("watchedSource"))
                                .putExtra("watchedTitle", call.argument<String>("watchedTitle"))
                                .putExtra("series", call.argument<Boolean>("series") ?: false))
                                result.success(null)
                            } catch (failure: Exception) {
                                TorrentEngine.submit(activity, JSONObject().put("method", "closeStream").put("id", id))
                                result.error("torrent", failure.message, null)
                            }
                        }.onFailure { result.error("torrent", it.message, null) }
                    }
                }
                "torrentImport" -> {
                    check(picker == null) { "Выбор файла уже открыт" }
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
                        .addCategory(Intent.CATEGORY_OPENABLE), 620)
                    picker = result
                }
                "torrentAdd" -> {
                    TorrentService.start(activity)
                    val origin = call.argument<Map<String, String>>("origin") ?: mapOf("local" to "magnet")
                    TorrentEngine.add(activity, call.argument<ByteArray>("bytes"), call.argument<String>("magnet"), JSONObject(origin), reply(result))
                }
                "torrentPlay" -> {
                    val id = call.argument<String>("id")
                    require(TorrentPolicy.id(id))
                    TorrentService.start(activity)
                    PlayerColors.configure(activity, call.argument<Boolean>("playerDark") != false)
                                activity.startActivity(Intent(activity, PlayerActivity::class.java).putExtra("torrentId", id)
                        .putExtra("title", call.argument<String>("title"))
                                .putExtra("watchedSource", call.argument<String>("watchedSource"))
                                .putExtra("watchedTitle", call.argument<String>("watchedTitle"))
                                .putExtra("series", call.argument<Boolean>("series") ?: false))
                    result.success(null)
                }
                "torrentCommand" -> {
                    val args = JSONObject(call.argument<Map<String, Any?>>("request") ?: emptyMap<String, Any?>())
                    val method = args.optString("method")
                    require(method in setOf("status", "pause", "resume", "remove", "limits"))
                    if (method !in setOf("status", "limits")) require(TorrentPolicy.id(args.optString("id")))
                    if (method == "resume") TorrentService.start(activity)
                    TorrentEngine.submit(activity, args, reply(result))
                }
                else -> result.notImplemented()
            }
        } catch (failure: Exception) { result.error("torrent", failure.message, null) }
    }
    fun activityResult(request: Int, code: Int, data: Intent?) {
        if (request != 620) return
        val result = picker ?: return
        picker = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(null); return }
        TorrentService.start(activity)
        // Provider I/O can block, never copy a document on the main looper.
        Executors.newSingleThreadExecutor().also { executor -> executor.execute {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val out = java.io.ByteArrayOutputStream(); val block = ByteArray(65536)
                    while (true) {
                        val count = input.read(block); if (count < 0) break
                        require(out.size() + count <= 16 * 1024 * 1024) { "Файл .torrent слишком большой" }
                        out.write(block, 0, count)
                    }
                    out.toByteArray()
                } ?: throw IllegalArgumentException("Не удалось прочитать файл")
                TorrentEngine.add(activity, bytes, null, JSONObject().put("local", "torrentFile"), reply(result))
            } catch (failure: Exception) { activity.runOnUiThread { result.error("torrent", failure.message, null) } }
            finally { executor.shutdown() }
        } }
    }
    fun close() { picker?.success(null); picker = null }
}
