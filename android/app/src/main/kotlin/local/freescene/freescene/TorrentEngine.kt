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
import java.security.KeyStore
import java.util.concurrent.Executors

@Keep
object TorrentNative {
    init { System.loadLibrary("FreeSceneEngine") }
    external fun create(config: String): Long
    external fun command(handle: Long, request: String): String
    external fun destroy(handle: Long)
}

/** One serialized native session for both Flutter and the platform player. */
object TorrentEngine {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var handle = 0L
    private var tvTask: String? = null
    private fun tvCache(context: Context) = File(context.cacheDir, "torrent-playback")
    private fun closeTvStream(context: Context) {
        if (handle != 0L) TorrentNative.destroy(handle)
        handle = 0L; tvTask = null
        synchronized(streams) { streams.clear() }
        tvCache(context).deleteRecursively()
    }
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
        val ca = File(profile, "ca.pem")
        val store = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
        ca.writeText(store.aliases().toList().mapNotNull { store.getCertificate(it) }.joinToString("\n") {
            "-----BEGIN CERTIFICATE-----\n" + android.util.Base64.encodeToString(it.encoded, android.util.Base64.NO_WRAP)
                .chunked(64).joinToString("\n") + "\n-----END CERTIFICATE-----"
        })
        val lite = TvWindow.isTv(context) || (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice
        handle = TorrentNative.create(JSONObject().put("profile", profile.path).put("downloads", downloads.path)
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
                if (args.optString("method") == "closeStream") {
                    if (TvWindow.isTv(app) && tvTask == args.optString("id")) closeTvStream(app)
                    return@runCatching JSONObject().put("ok", true)
                }
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
            val result = runCatching {
                require(bytes != null || TorrentPolicy.magnet(magnet)) { "Нужна magnet-ссылка или .torrent" }
                if (TvWindow.isTv(app) && tvTask != null) closeTvStream(app)
                initialize(app)
                val args = JSONObject().put("method", "add").put("origin", origin)
                if (bytes != null) {
                    require(bytes.size in 1..16 * 1024 * 1024 && bytes[0] == 'd'.code.toByte()) { "Некорректный .torrent" }
                    temp = File.createTempFile("import-", ".torrent", app.cacheDir).apply { writeBytes(bytes) }
                    args.put("source", temp!!.path)
                    if (magnet != null) { require(TorrentPolicy.magnet(magnet)); args.put("expectedMagnet", magnet) }
                } else args.put("source", magnet)
                command(args).also { result ->
                    if (TvWindow.isTv(app)) tvTask = result.getString("id")
                    if (result.optBoolean("duplicate")) command(JSONObject().put("method", "resume").put("id", result.getString("id")))
                }
            }
            temp?.delete()
            main.post { callback(result) }
        }
    }
    fun trustedStream(url: String?) = synchronized(streams) { url != null && streams.contains(url) }
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
