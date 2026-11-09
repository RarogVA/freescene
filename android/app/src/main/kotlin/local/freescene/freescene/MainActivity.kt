package local.freescene.freescene

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.app.ActivityManager
import android.content.Intent
import org.json.JSONArray
import android.view.KeyEvent

class MainActivity : FlutterActivity() {
    private val updates by lazy { AndroidUpdates(this) }
    private val downloadNotifications by lazy { DownloadNotifications(this) }
    private val remoteBack = RemoteBack()
    private val torrents by lazy { TorrentChannel(this) }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // TV remotes otherwise emit both a Flutter key-down and Android popRoute
        // on key-up, dismissing the dialog that the first event just opened.
        if (remoteBack.dispatch(event) { flutterEngine?.navigationChannel?.popRoute() }) return true
        return super.dispatchKeyEvent(event)
    }
    private val speech by lazy { VoiceSearch(this) }
    private var voiceEvents: EventChannel.EventSink? = null
    private val embeddedSpeech by lazy { EmbeddedVoiceSearch(this) { voiceEvents?.success(it) } }
    @Deprecated("Activity result API used by the Flutter activity host")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        speech.activityResult(requestCode, resultCode, data)
        torrents.activityResult(requestCode, resultCode, data)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        speech.permissionResult(requestCode, permissions, grantResults)
        embeddedSpeech.permissionResult(requestCode, permissions, grantResults)
        downloadNotifications.complete(requestCode)
    }
    override fun onDestroy() {
        speech.cancel()
        embeddedSpeech.cancel()
        torrents.close()
        downloadNotifications.cancel()
        super.onDestroy()
    }
    override fun onResume() { super.onResume(); TvWindow.apply(this); UpdateRestart.resumed(this) }
    override fun onStop() {
        embeddedSpeech.hostStopped()
        super.onStop()
    }
    override fun onWindowFocusChanged(focused: Boolean) {
        super.onWindowFocusChanged(focused)
        if (focused) TvWindow.apply(this)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "freescene/voice")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) { voiceEvents = events }
                override fun onCancel(arguments: Any?) { voiceEvents = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "freescene/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "torrentOpen" -> torrents.call(call, result)
                    "torrentAdd", "torrentPlay", "torrentImport" -> if (TvWindow.isTv(this)) torrents.call(call, result)
                        else downloadNotifications.run(result) { torrents.call(call, result) }
                    "torrentCommand" -> if (!TvWindow.isTv(this) && call.argument<Map<String, Any?>>("request")?.get("method") == "resume") {
                        downloadNotifications.run(result) { torrents.call(call, result) }
                    } else torrents.call(call, result)
                    "updateCheck", "updateDownload" ->
                        updates.request(call.method, result)
                    "updateInstall" -> downloadNotifications.run(result) { updates.install(this, result) }
                    "playWeb" -> {
                        val provider = call.argument<String>("provider")
                        val url = call.argument<String>("url")
                        val index = call.argument<Int>("webPlayer") ?: 0
                        val episodes = call.argument<List<Map<String, Any?>>>("episodes") ?: emptyList()
                        if (!WebPolicy.player(provider, url) || index !in 0..7 || episodes.size > 400) {
                            result.error("invalid_url", "Invalid web player reference", null)
                        } else {
                            val safeEpisodes = episodes.mapNotNull { item ->
                                val link = item["url"] as? String
                                val title = (item["title"] as? String)?.take(512)
                                if (provider != null && url != null && WebPolicy.sameTitle(provider, link, url) && !title.isNullOrEmpty())
                                    mapOf("url" to link, "title" to title) else null
                            }
                            startActivity(Intent(this, WebPlayerActivity::class.java)
                                .putExtra("title", call.argument<String>("title"))
                                .putExtra("provider", provider).putExtra("url", url).putExtra("webPlayer", index)
                                .putExtra("episodes", JSONArray(safeEpisodes).toString()))
                            result.success(null)
                        }
                    }
                    "voiceSearch" -> speech.start(call.argument<String>("language"), result)
                    "voiceListen" -> embeddedSpeech.start(call.argument<String>("language"), result)
                    "voiceCancel" -> { embeddedSpeech.cancel(); result.success(null) }
                    "runtime" -> result.success(mapOf(
                        "profile" to filesDir.absolutePath,
                        "cache" to cacheDir.absolutePath,
                        "tv" to TvWindow.isTv(this),
                        "lowRam" to (getSystemService(ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice,
                        "version" to BuildConfig.VERSION_NAME
                    ))
                    "play" -> {
                        val url = call.argument<String>("url")
                        if (!PlaybackPolicy.allowed(url)) result.error("invalid_url", "HTTPS media required", null)
                        else {
                            startActivity(Intent(this, PlayerActivity::class.java)
                                .putExtra("url", url).putExtra("title", call.argument<String>("title"))
                                .putExtra("playbackId", call.argument<String>("playbackId"))
                                .putExtra("referrer", call.argument<String>("referrer"))
                                .putExtra("mimeType", call.argument<String>("mimeType")))
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
