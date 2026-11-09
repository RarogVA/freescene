package local.freescene.freescene

import local.freescene.provider_host.ProviderHost
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject

/** A data-only channel: a page can report time for this session, never choose a history key. */
class WebPlaybackProgress(private val received: (PlaybackHistory.Point, Boolean) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    @JavascriptInterface fun postMessage(message: String) {
        val report = parse(message) ?: return
        main.post { received(report.first, report.second) }
    }

    fun install(browser: WebView, source: String) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(browser, "FreeScenePlayback", setOf("*")) { _, message, _, _, _ ->
                message.data?.let { postMessage(it) }
            }
        } else {
            // Older WebViews expose only this bounded, write-only progress method.
            browser.addJavascriptInterface(this, "FreeScenePlayback")
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(browser, source, setOf("*"))
        }
    }

    companion object {
        fun script(browser: WebView, provider: String, position: Long, duration: Long): String {
            val source = browser.context.assets.open("flutter_assets/assets/player/progress.js")
                .bufferedReader().use { it.readText() }
            val config = JSONObject().put("rootSelector", ProviderHost.web?.rootSelector(provider)).put("position", position).put("duration", duration)
            return "($source)($config);"
        }
        fun parse(message: String): Pair<PlaybackHistory.Point, Boolean>? = try {
            if (message.length > 512) null else {
                val data = JSONObject(message)
                val position = data.getDouble("position")
                val duration = data.getDouble("duration")
                if (!position.isFinite() || !duration.isFinite() || position < 0 ||
                    duration <= 0 || duration > PlaybackHistory.MAX_TIME || position > duration + 1000) null
                else PlaybackHistory.Point(position.toLong().coerceAtMost(duration.toLong()), duration.toLong()) to data.optBoolean("ended")
            }
        } catch (_: Exception) { null }
    }
}
