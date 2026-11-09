package local.freescene.freescene

import android.content.Context
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

object PlayerPresentation {
    fun script(context: Context, mode: Int): String {
        val source = context.assets.open("flutter_assets/assets/player/presentation.js").bufferedReader().use { it.readText() }
        return "($source)(${mode.takeIf { it in 0..2 } ?: 0});"
    }

    fun install(browser: WebView, mode: Int) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            // Includes cross-origin providers nested inside the selected provider iframe.
            WebViewCompat.addDocumentStartJavaScript(browser, script(browser.context, mode), setOf("*"))
        }
    }
}
