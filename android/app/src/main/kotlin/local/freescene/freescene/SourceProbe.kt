package local.freescene.freescene

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** One bounded, disposable probe; never uses the playback engine or its cache. */
object SourceProbe {
    private val worker = Executors.newSingleThreadExecutor()
    private val epoch = AtomicInteger()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var connection: HttpURLConnection? = null
    fun cancel() { epoch.incrementAndGet(); connection?.disconnect() }
    fun start(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val generation = epoch.get()
        val bytes = call.argument<ByteArray>("bytes")
        val magnet = call.argument<String>("magnet")
        val season = call.argument<Int>("season") ?: -1
        val episode = call.argument<Int>("episode") ?: -1
        if ((bytes == null && magnet == null) ||
            (bytes != null && (bytes.size !in 1..16*1024*1024 || bytes[0] != 'd'.code.toByte())) ||
            (magnet != null && !TorrentPolicy.magnet(magnet))) {
            result.success("unavailable"); return
        }
        worker.execute {
            val directory = File(context.cacheDir, "source-probe").apply { deleteRecursively(); mkdirs() }
            var handle = 0L
            var status = "timeout"
            try {
                if (generation != epoch.get()) return@execute main.post { result.success("cancelled") }.let { }
                val ca = TorrentCertificates.bundle(context)
                handle = TorrentNative.create(JSONObject().put("profile", File(directory,"profile").path).put("downloads", File(directory,"buffer").path)
                    .put("lite",true).put("streamOnly",true).put("caBundle",ca.path).toString())
                check(handle != 0L)
                fun command(request: JSONObject): JSONObject {
                    val reply = JSONObject(TorrentNative.command(handle,request.toString()))
                    check(!reply.has("error"))
                    return reply.getJSONObject("result")
                }
                val source = if(bytes != null) File(directory,"source.torrent").apply { writeBytes(bytes) }.path else magnet!!
                val add = JSONObject().put("method","add").put("source",source)
                if(bytes != null && magnet != null) add.put("expectedMagnet",magnet)
                val id = command(add).getString("id")
                command(JSONObject().put("method","prepareStream").put("id",id))
                val until = System.nanoTime() + 20_000_000_000L
                var file = -1
                while(generation == epoch.get() && System.nanoTime() < until) {
                    val tasks = command(JSONObject().put("method","status")).getJSONArray("tasks")
                    if(tasks.length()>0) {
                        val files = tasks.getJSONObject(0).getJSONArray("files")
                        val videos = (0 until files.length()).map { files.getJSONObject(it) }.filter { it.optBoolean("video") }
                        file = TorrentEpisode.probeIndex(videos, season, episode) ?: -1
                        // Do not certify another episode when the requested file is ambiguous.
                        if (videos.isNotEmpty()) break
                    }
                    if(file>=0) break
                    Thread.sleep(200)
                }
                if(file>=0 && generation==epoch.get() && System.nanoTime() < until) {
                    val url=command(JSONObject().put("method","stream").put("id",id).put("file",file)).getString("url")
                    val http=URL(url).openConnection() as HttpURLConnection
                    connection=http
                    http.connectTimeout=2000
                    http.readTimeout=((until-System.nanoTime())/1_000_000).coerceIn(1,20000).toInt()
                    http.setRequestProperty("Range","bytes=0-65535")
                    status = if(http.responseCode==206) http.inputStream.use { if(it.read()>=0) "data" else "unavailable" } else "unavailable"
                }
                if(generation != epoch.get()) status="cancelled"
            } catch (_: SocketTimeoutException) { status = if(generation != epoch.get()) "cancelled" else "timeout" }
            catch (_: Exception) { status = if(generation != epoch.get()) "cancelled" else "unavailable" }
            finally {
                connection?.disconnect(); connection=null
                if(handle!=0L) TorrentNative.destroy(handle)
                directory.deleteRecursively()
            }
            main.post { result.success(status) }
        }
    }
}
