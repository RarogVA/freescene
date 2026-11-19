package local.freescene.freescene

import android.app.ActivityManager
import android.content.Context
import android.os.Environment
import android.os.Handler
import android.os.Looper
import androidx.annotation.Keep
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@Keep
object TorrentNative {
    init { System.loadLibrary("FreeSceneEngine") }
    external fun create(config: String): Long
    external fun command(handle: Long, request: String): String
    external fun destroy(handle: Long)
}

/** One serialized native session for both Flutter and the platform player. */
object TorrentEngine {
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var handle = 0L
    private var tvSession: TvTorrentSession? = null
    private fun historyCache(context: Context) = File(context.filesDir, "watch-history-network")
    fun syncWatchHistory(context: Context, task: String? = null, file: Int = -1, callback: (Result<Unit>) -> Unit = {}) {
        val app = context.applicationContext
        worker.execute {
            val result = runCatching {
                val ids = WatchHistory(app).ids()
                if (handle != 0L) {
                    command(JSONObject().put("method", "historyCacheSync").put("ids", JSONArray(ids)))
                    if (task != null && file >= 0) command(JSONObject().put("method", "historyCacheRecord").put("id", task).put("file", file))
                } else {
                    val root = historyCache(app)
                    root.listFiles()?.filter { it.name !in ids }?.forEach { check(it.deleteRecursively()) }
                    if (ids.isEmpty() && root.exists()) check(root.deleteRecursively())
                }
                Unit
            }
            main.post { callback(result) }
        }
    }
    private fun tvCache(context: Context) = File(context.cacheDir, "torrent-playback")
    private fun closeTvStream(context: Context) {
        if (handle != 0L) TorrentNative.destroy(handle)
        handle = 0L
        synchronized(streams) { streams.clear() }
        tvCache(context).deleteRecursively()
    }
    private fun tvSession(context: Context): TvTorrentSession = tvSession ?: TvTorrentSession(
        dispose = { closeTvStream(context) },
        scheduleExpiry = { action ->
            val pending = worker.schedule({ action() }, 2, TimeUnit.MINUTES)
            val cancel: () -> Unit = { pending.cancel(false) }
            cancel
        },
    ).also { tvSession = it }
    private val streams = mutableSetOf<String>()
    private fun initialize(context: Context) {
        if (handle != 0L) return
        val tv = TvWindow.isTv(context)
        // A TV session is disposable. Also remove leftovers after a process crash.
        val cache = tvCache(context)
        if (tv) cache.deleteRecursively()
        val profile = (if (tv) File(cache, "profile") else File(context.filesDir, "torrents")).apply { mkdirs() }
        val downloads = (if (tv) File(cache, "buffer") else
            File(context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: context.filesDir, "torrents")).apply { mkdirs() }
        // OpenSSL does not read Android's certificate store by itself.
        val ca = TorrentCertificates.bundle(context)
        val lite = TvWindow.isTv(context) || (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice
        handle = TorrentNative.create(JSONObject().put("profile", profile.path).put("downloads", downloads.path)
            .put("historyCache", historyCache(context).path).put("historyIds", JSONArray(WatchHistory(context).ids()))
            .put("lite", lite).put("streamOnly", tv).put("pauseOnRestore", true).put("caBundle", ca.path).toString())
        if (handle == 0L) throw IllegalStateException("Не удалось запустить торрент-движок")
    }
    private fun command(args: JSONObject): JSONObject {
        val reply = JSONObject(TorrentNative.command(handle, args.toString()))
        if (reply.has("error")) throw IllegalStateException(reply.getString("error"))
        return reply.getJSONObject("result")
    }
    fun submit(context: Context, args: JSONObject, callback: (Result<JSONObject>) -> Unit = {}) {
        val app = context.applicationContext
        worker.execute {
            val result = runCatching {
                val tv = TvWindow.isTv(app)
                val method = args.optString("method")
                val current = !tv || tvSession(app).owns(args.optString("id"), args.optLong("playbackSession", -1))
                if (method == "closeStream") {
                    if (tv && current) {
                        command(JSONObject().put("method", "pause").put("id", args.getString("id")))
                        tvSession(app).release(args.getString("id"), args.getLong("playbackSession"))
                    }
                    return@runCatching JSONObject().put("ok", true)
                }
                check(current) { "Сеанс воспроизведения уже закрыт" }
                initialize(app)
                val response = command(args)
                if (args.optString("method") == "stream") synchronized(streams) { streams.add(response.getString("url")) }
                response
            }
            main.post { callback(result) }
        }
    }
    fun add(context: Context, bytes: ByteArray?, magnet: String?, origin: JSONObject, callback: (Result<JSONObject>) -> Unit) {
        val app = context.applicationContext
        worker.execute {
            var temp: File? = null
            var prepared = false
            val result = runCatching {
                require(bytes != null || TorrentPolicy.magnet(magnet)) { "Нужна magnet-ссылка или .torrent" }
                if (bytes != null) require(bytes.size in 1..16 * 1024 * 1024 && bytes[0] == 'd'.code.toByte()) { "Некорректный .torrent" }
                if (magnet != null) require(TorrentPolicy.magnet(magnet))
                val tv = TvWindow.isTv(app)
                if (tv) {
                    // Providers can supply a stable magnet alongside refreshed metadata.
                    // Native add still validates expectedMagnet before reusing a task.
                    val source = magnet ?: MessageDigest.getInstance("SHA-256").digest(bytes!!)
                        .joinToString("") { "%02x".format(it) }
                    tvSession(app).prepare(source)
                    prepared = true
                }
                initialize(app)
                val args = JSONObject().put("method", "add").put("origin", origin)
                if (bytes != null) {
                    temp = File.createTempFile("import-", ".torrent", app.cacheDir).apply { writeBytes(bytes) }
                    args.put("source", temp!!.path)
                    if (magnet != null) args.put("expectedMagnet", magnet)
                } else args.put("source", magnet)
                command(args).also { result ->
                    if (tv) result.put("playbackSession", tvSession(app).opened(result.getString("id")))
                    if (!tv && result.optBoolean("duplicate")) command(JSONObject().put("method", "resume").put("id", result.getString("id")))
                }
            }.onFailure { if (prepared) tvSession(app).abort() }
            temp?.delete()
            main.post { callback(result) }
        }
    }
    fun trustedStream(url: String?) = synchronized(streams) { url != null && streams.contains(url) }
    fun replayHistory(context: Context, owner: String, callback: (Result<JSONObject>) -> Unit) {
        val app = context.applicationContext
        worker.execute {
            val tv = TvWindow.isTv(app)
            val result = runCatching {
                require(WatchHistory(app).entry(owner)?.optString("sourceType") == "torrent")
                if (tv) tvSession(app).prepare("history:$owner")
                initialize(app)
                command(JSONObject().put("method", "historyCacheSync").put("ids", JSONArray(WatchHistory(app).ids())))
                command(JSONObject().put("method", "historyReplay").put("owner", owner)).also {
                    if (tv) it.put("playbackSession", tvSession(app).opened(it.getString("id")))
                }
            }.onFailure { if (tv) tvSession(app).abort() }
            main.post { callback(result) }
        }
    }
    fun pauseAll(context: Context, callback: () -> Unit = {}) {
        submit(context, JSONObject().put("method", "status")) { result ->
            val tasks = result.getOrNull()?.optJSONArray("tasks") ?: JSONArray()
            for (i in 0 until tasks.length()) submit(context, JSONObject().put("method", "pause").put("id", tasks.getJSONObject(i).getString("id")))
            worker.execute { main.post(callback) }
        }
    }
    fun map(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { map(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { map(value.get(it)) }
        else -> value
    }
}

object TorrentPolicy {
    fun magnet(value: String?): Boolean = try {
        val uri = android.net.Uri.parse("https://magnet.invalid/?" + value?.substringAfter('?', ""))
        value != null && value.length <= 65536 && value.startsWith("magnet:?") &&
            uri.getQueryParameters("xt").any { Regex("urn:btih:([a-fA-F0-9]{40}|[A-Za-z2-7]{32})|urn:btmh:1220[a-fA-F0-9]{64}").matches(it) }
    } catch (_: Exception) { false }
    fun id(value: String?) = value != null && Regex("[a-f0-9]{40}|[a-f0-9]{64}").matches(value)
}
