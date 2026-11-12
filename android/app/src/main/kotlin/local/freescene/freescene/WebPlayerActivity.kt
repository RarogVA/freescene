package local.freescene.freescene
import local.freescene.provider_host.ProviderHost

import android.app.Activity
import android.app.AlertDialog
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.*
import android.widget.*
import org.json.JSONArray
import java.io.ByteArrayInputStream

/** The provider owns playback. The app always owns an accessible exit. */
open class WebPlayerActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private var generation = 0
    private var active = false
    private var web: WebView? = null
    private var custom: View? = null
    private var customCallback: WebChromeClient.CustomViewCallback? = null
    private lateinit var surface: FrameLayout
    private lateinit var close: PlayerCloseButton
    private lateinit var scale: PlayerScaleControl
    private lateinit var controls: Button
    private lateinit var playPause: ImageButton
    private var resumed = false
    private var tvFocus: TvPlayerFocus? = null
    private var webSettings: WebPlayerSettings? = null
    private var settingsFocus: View? = null
    private lateinit var status: TextView
    private lateinit var providerNotice: TextView
    private lateinit var pointer: RemotePointer
    private lateinit var provider: String
    private lateinit var source: String
    private var playerIndex = 0
    private var idleControls: TvIdleControls? = null
    private val watchedClock = WatchedClock { WatchedHistory(this).set(intent.getStringExtra("watchedSource"), intent.getStringExtra("watchedTitle"), true) }
    private val history by lazy { PlaybackHistory(this) }
    private var preparedSource: String? = null
    private var resumePosition = -1L
    private var resumeDuration = 0L
    private var resumeDialog: AlertDialog? = null
    private val episodes = mutableListOf<Pair<String, String>>()
    private fun text(ru: String, en: String) = if (resources.configuration.locales[0].language == "ru") ru else en
    protected open fun makeWebView(): WebView = WebView(this)
    protected open fun prepareSession(done: (Boolean) -> Unit) {
        ProviderHost.web?.prepare(this, provider, done) ?: done(false)
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        PlayerColors.restore(this)
        watchedClock.elapsed = state?.getLong("watchedElapsed") ?: 0
        provider = intent.getStringExtra("provider") ?: ""
        source = state?.getString("source") ?: intent.getStringExtra("url") ?: ""
        preparedSource = state?.getString("preparedSource")
        playerIndex = intent.getIntExtra("webPlayer", 0)
        if (!WebPolicy.player(provider, source) || playerIndex !in 0..7) { finish(); return }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        try {
            val values = JSONArray(intent.getStringExtra("episodes") ?: "[]")
            for (i in 0 until values.length().coerceAtMost(400)) {
                val item = values.getJSONObject(i)
                val url = item.optString("url"); val title = item.optString("title")
                if (WebPolicy.sameTitle(provider, url, source) && title.length in 1..512) episodes.add(title to url)
            }
        } catch (_: Exception) { episodes.clear() }
        val bar = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setBackgroundColor(PlayerColors.panel) }
        fun button(label: String, action: () -> Unit): Button = Button(this).apply {
            id = View.generateViewId(); text = label; isFocusableInTouchMode = TvWindow.isTv(this@WebPlayerActivity)
            backgroundTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_focused), intArrayOf()),
                intArrayOf(PlayerColors.accent, PlayerColors.raised))
            setTextColor(ColorStateList(arrayOf(intArrayOf(android.R.attr.state_focused), intArrayOf()),
                intArrayOf(PlayerColors.onAccent, PlayerColors.text)))
            if (TvWindow.isTv(this@WebPlayerActivity)) {
                TvButtonFocus.apply(this)
                setTextColor(PlayerColors.text)
            }
            setOnClickListener { action() }
            bar.addView(this, LinearLayout.LayoutParams(-2, -2).apply {
                val gap = (4 * resources.displayMetrics.density).toInt()
                setMargins(gap, gap, gap, gap)
            })
        }
        close = PlayerCloseButton(this).apply { tag = "player-close"; setOnClickListener { finish() } }
        bar.addView(close, LinearLayout.LayoutParams(close.diameter, close.diameter).apply {
            val inset = (8 * resources.displayMetrics.density).toInt()
            setMargins(inset, inset, inset, inset)
        })
        bar.addView(PlayerTitleView(this, intent.getStringExtra("title")), LinearLayout.LayoutParams(0, close.diameter, 1f))
        playPause = PlayerCloseButton(this).apply {
            tag = "player-play-pause"
            contentDescription = text("Воспроизведение / Пауза", "Play / Pause")
            setImageResource(android.R.drawable.ic_media_play)
            visibility = if (TvWindow.isTv(this@WebPlayerActivity)) View.VISIBLE else View.GONE
            setOnClickListener { web?.evaluateJavascript("window.__freescenePlayback?.toggle();", null) }
        }
        bar.addView(playPause, LinearLayout.LayoutParams(close.diameter, close.diameter))
        if (intent.getBooleanExtra("series", false) && episodes.size > 1) button(text("Серии", "Episodes")) { chooseEpisode() }
        scale = PlayerScaleControl(this, state?.getInt("scaleMode") ?: 0,
            opened = { idleControls?.stop() },
            dismissed = { if (active) { TvWindow.applyPlayer(this); idleControls?.start() } },
            changed = { mode -> web?.let { it.evaluateJavascript(PlayerPresentation.script(this, mode), null) } })
        webSettings = WebPlayerSettings(this,
            send = { command -> web?.evaluateJavascript("window.__freescenePlayback?.command($command);", null) },
            opened = { idleControls?.stop() },
            dismissed = { if (active) { idleControls?.start(); if (TvWindow.isTv(this)) settingsFocus?.requestFocus() } },
            scaling = { scale.button.performClick() })
        fun setting(icon: Int, label: String, action: () -> Unit) = PlayerCloseButton(this).apply {
            contentDescription = label; setImageResource(icon)
            tag = "player-setting-$label"
            setOnClickListener { settingsFocus = this; action() }
            bar.addView(this, LinearLayout.LayoutParams(diameter, diameter))
        }
        if (TvWindow.isTv(this)) {
            setting(R.drawable.ic_player_audio, text("Аудио", "Audio")) { webSettings?.request("audio") }
            setting(androidx.media3.ui.R.drawable.exo_ic_speed, text("Скорость", "Speed")) { webSettings?.request("speed") }
            setting(androidx.media3.ui.R.drawable.exo_ic_subtitle_on, text("Субтитры", "Subtitles")) { webSettings?.request("text") }
        } else setting(androidx.media3.ui.R.drawable.exo_ic_settings, text("Настройки", "Settings")) { webSettings?.menu() }
        button(text("Повторить", "Retry")) { load() }
        controls = button(text("Плеер", "Player")) { pointer.requestFocus() }
        controls.visibility = if (TvWindow.isTv(this)) View.VISIBLE else View.GONE
        bar.addView(scale.button, LinearLayout.LayoutParams(scale.button.diameter, scale.button.diameter).apply {
            val inset = (8 * resources.displayMetrics.density).toInt()
            setMargins(inset, inset, inset, inset)
        })
        if (!TvWindow.isTv(this)) scale.button.visibility = View.GONE
        surface = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        val tv = TvWindow.isTv(this)
        val content = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            // Overlay controls: hiding them must not resize/reload the web video.
            addView(surface, FrameLayout.LayoutParams(-1, -1))
            addView(bar, FrameLayout.LayoutParams(-1, -2, Gravity.TOP))
        }
        pointer = RemotePointer(this) { custom ?: web }.apply {
            id = View.generateViewId()
            visibility = if (TvWindow.isTv(this@WebPlayerActivity)) View.VISIBLE else View.GONE
            returnToToolbar = { controls.requestFocus() }
        }
        controls.nextFocusDownId = pointer.id
        status = TextView(this).apply { setTextColor(PlayerColors.text); gravity = Gravity.BOTTOM or Gravity.START; setPadding(24, 12, 24, 24); setBackgroundColor(Color.TRANSPARENT) }
        providerNotice = TextView(this).apply {
            val name = intent.getStringExtra("providerName")?.take(128) ?: provider
            text = text("Официальный плеер «$name»", "Official player “$name”")
            gravity = Gravity.CENTER; setTextColor(PlayerColors.text)
            setBackgroundColor(android.graphics.Color.argb(210, 34, 36, 41))
            setPadding(12, 6, 12, 6); visibility = View.GONE
        }
        content.addView(providerNotice, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(content)
        if (tv) tvFocus = TvPlayerFocus(content) { playPause }
        idleControls = TvIdleControls(true) { visible ->
            pointer.cursorVisible = visible
            if (::providerNotice.isInitialized) providerNotice.visibility = if (visible && status.visibility == View.GONE) View.VISIBLE else View.GONE
            if (visible) {
                bar.visibility = View.VISIBLE
                if (tv) {
                    tvFocus?.restore(force = true)
                }
            } else {
                tvFocus?.remember()
                bar.visibility = View.INVISIBLE
                if (tv) pointer.requestFocus()
            }
        }
    }
    private fun chooseEpisode() {
        idleControls?.stop()
        val original = window.decorView.findFocus()
        val selected = episodes.indexOfFirst { it.second == source }
        val dialog = AlertDialog.Builder(this).setTitle(text("Сезоны и серии", "Seasons and episodes"))
            .setSingleChoiceItems(episodes.map { it.first }.toTypedArray(), selected) { d, i ->
                source = episodes[i].second; d.dismiss(); load()
            }.setNegativeButton(text("Отмена", "Cancel"), null).create()
        dialog.setOnDismissListener { if (TvWindow.isTv(this)) original?.requestFocus(); TvWindow.applyPlayer(this); idleControls?.start() }
        dialog.show()
        if (TvWindow.isTv(this)) dialog.listView.requestFocus()
        if (selected >= 0) dialog.listView.setSelection(selected)
    }
    @Suppress("SetJavaScriptEnabled")
    private fun load() {
        releaseWeb()
        if (!active || isFinishing || resumeDialog != null) return
        val key = PlaybackHistory.webKey(provider, source)
        val saved = history.read(key)
        fun begin(position: Long) {
            if (!active || isFinishing) return
            preparedSource = source
            resumePosition = position
            resumeDuration = saved?.duration ?: 0
            loadWeb()
        }
        if (preparedSource == source || saved == null) {
            begin(saved?.position ?: -1)
            return
        }
        idleControls?.stop()
        resumeDialog = PlaybackResumeDialog.show(this, saved.position,
            selected = { resume ->
                if (!resume) history.clear(key)
                begin(if (resume) saved.position else 0)
            },
            cancelled = { finish() },
            dismissed = { resumeDialog = null; if (active) idleControls?.start() })
    }
    @Suppress("SetJavaScriptEnabled")
    private fun loadWeb() {
        releaseWeb()
        val epoch = generation
        if (!active || isFinishing) return
        providerNotice.visibility = View.GONE
        status.text = text("Загрузка…", "Loading…")
        status.visibility = View.VISIBLE
        surface.addView(status, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        prepareSession { available ->
            if (!active || isFinishing || epoch != generation) return@prepareSession
            if (!available) { failed(); return@prepareSession }
            try {
                val browser = makeWebView()
                web = browser
                browser.setBackgroundColor(Color.BLACK)
                browser.isFocusable = !TvWindow.isTv(this)
                browser.settings.apply {
                    javaScriptEnabled = true; domStorageEnabled = true
                    allowFileAccess = false; allowContentAccess = false
                    mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                    mediaPlaybackRequiresUserGesture = true
                    javaScriptCanOpenWindowsAutomatically = false
                    setSupportMultipleWindows(true)
                }
                PlayerPresentation.install(browser, scale.mode)
                val progressScript = WebPlaybackProgress.script(browser, provider, resumePosition, resumeDuration)
                val progressKey = PlaybackHistory.webKey(provider, source)
                WebPlaybackProgress(received = { point, ended ->
                    if (active && epoch == generation && browser === web) {
                        history.save(progressKey, point.position, point.duration, ended)
                    }
                }, playing = { playing ->
                    if (active && epoch == generation && browser === web) {
                        watchedClock.sample(resumed && playing)
                        playPause.setImageResource(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
                    }
                }, controls = { data -> if (active && epoch == generation && browser === web) webSettings?.received(data) }).install(browser, progressScript)
                CookieManager.getInstance().setAcceptThirdPartyCookies(browser, true)
                browser.setDownloadListener { _, _, _, _, _ -> /* External downloads are not a player action. */ }
                browser.webChromeClient = object : WebChromeClient() {
                    override fun onCreateWindow(v: WebView?, dialog: Boolean, gesture: Boolean, result: android.os.Message?) = false
                    override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                    override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                        if (custom != null) { callback.onCustomViewHidden(); return }
                        custom = view; customCallback = callback
                        view.setBackgroundColor(Color.BLACK)
                        surface.addView(view, FrameLayout.LayoutParams(-1, -1))
                        pointer.bringToFront(); TvWindow.applyPlayer(this@WebPlayerActivity)
                    }
                    override fun onHideCustomView() { hideCustom() }
                }
                browser.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean =
                        !WebPolicy.navigation(provider, r.url.toString(), source, r.isForMainFrame)
                    override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse? =
                        if (ProviderHost.web?.blockedRequest(provider, r.url.toString()) == true)
                            WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0))) else null
                    override fun onPageFinished(v: WebView, url: String) {
                        if (epoch != generation || !active) return
                        if (!WebPolicy.navigation(provider, url, source, true)) { failed(); return }
                        v.evaluateJavascript(PlayerPresentation.script(this@WebPlayerActivity, scale.mode), null)
                        v.evaluateJavascript(progressScript, null)
                        if (ProviderHost.web?.script(provider, playerIndex) == null) { status.visibility = View.GONE; providerNotice.visibility = barVisibility() }
                    }
                    override fun onReceivedError(v: WebView, r: WebResourceRequest, error: WebResourceError) {
                        if (r.isForMainFrame && epoch == generation) failed()
                    }
                    override fun onReceivedHttpError(v: WebView, r: WebResourceRequest, response: WebResourceResponse) {
                        if (r.isForMainFrame && epoch == generation) failed()
                    }
                    override fun onRenderProcessGone(v: WebView, detail: RenderProcessGoneDetail): Boolean {
                        if (v === web) { releaseWeb(); failed() }
                        return true
                    }
                }
                status.visibility = View.VISIBLE
                surface.addView(browser, 0, FrameLayout.LayoutParams(-1, -1))
                surface.addView(pointer, FrameLayout.LayoutParams(-1, -1))
                browser.loadUrl(source)
                if (ProviderHost.web?.script(provider, playerIndex) != null) inspect(epoch, 0)
                main.postDelayed({ if (epoch == generation && status.visibility == View.VISIBLE) failed() }, 30000)
            } catch (_: RuntimeException) { releaseWeb(); failed() }
        }
    }
    private fun inspect(epoch: Int, attempt: Int) {
        if (!active || epoch != generation || attempt >= 60) return
        val browser = web ?: return
        browser.evaluateJavascript(ProviderHost.web?.script(provider, playerIndex) ?: return) { result ->
            if (!active || epoch != generation) return@evaluateJavascript
            if (result == "true") { status.visibility = View.GONE; providerNotice.visibility = barVisibility() }
            else main.postDelayed({ inspect(epoch, attempt + 1) }, 500)
        }
    }
    private fun barVisibility() = if (close.isShown) View.VISIBLE else View.GONE
    private fun failed() {
        if (::providerNotice.isInitialized) providerNotice.visibility = View.GONE
        if (!::status.isInitialized || isFinishing) return
        status.text = text("Не удалось загрузить плеер. Повторите или выберите другой источник.", "Player unavailable. Retry or choose another source.")
        if (status.parent == null) surface.addView(status, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        status.visibility = View.VISIBLE; status.bringToFront(); idleControls?.interact()
        if (TvWindow.isTv(this)) close.requestFocus()
    }
    private fun hideCustom() {
        custom?.let { surface.removeView(it) }; custom = null
        val callback = customCallback; customCallback = null
        callback?.onCustomViewHidden()
    }
    private fun releaseWeb() {
        watchedClock.sample(false)
        webSettings?.dismiss()
        ++generation; main.removeCallbacksAndMessages(null)
        hideCustom()
        web?.let { v ->
            (v.parent as? ViewGroup)?.removeView(v)
            try { v.stopLoading(); v.onPause(); v.loadUrl("about:blank") } catch (_: RuntimeException) { /* Renderer may have died. */ }
            v.removeAllViews(); v.destroy()
        }
        web = null
        if (::surface.isInitialized) surface.removeAllViews()
    }
    override fun onStart() {
        super.onStart()
        if (!active) { active = true; if (!isFinishing) load() }
    }
    override fun onResume() { super.onResume(); resumed = true; TvWindow.applyPlayer(this); if (resumeDialog == null) idleControls?.start() }
    override fun onPause() {
        resumed = false
        watchedClock.sample(false)
        web?.evaluateJavascript("window.__freescenePlayback?.flush();", null)
        idleControls?.stop(); super.onPause()
    }
    override fun onWindowFocusChanged(focused: Boolean) {
        super.onWindowFocusChanged(focused)
        if (focused) { TvWindow.applyPlayer(this); if (resumeDialog == null) { idleControls?.start(); tvFocus?.restore() } } else idleControls?.stop()
    }
    override fun onStop() {
        idleControls?.stop(); active = false
        resumeDialog?.dismiss(); resumeDialog = null
        if (::scale.isInitialized) scale.dismiss()
        releaseWeb(); super.onStop()
    }
    override fun onDestroy() { idleControls?.stop(); active = false; releaseWeb(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        if (::source.isInitialized) out.putString("source", source)
        out.putString("preparedSource", preparedSource)
        out.putLong("watchedElapsed", watchedClock.elapsed)
        if (::scale.isInitialized) out.putInt("scaleMode", scale.mode)
        super.onSaveInstanceState(out)
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // Deliver to the original target before revealing the toolbar, so a wake
        // gesture cannot accidentally press a newly visible Close/Scale button.
        val handled = super.dispatchTouchEvent(event)
        idleControls?.interact()
        return handled
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (idleControls?.dispatch(event) == true) return true
        if (event.keyCode == KeyEvent.KEYCODE_BACK || event.keyCode == KeyEvent.KEYCODE_ESCAPE) {
            if (event.action == KeyEvent.ACTION_UP) finish()
            return true
        }
        if (idleControls?.visible == true && resumeDialog == null) tvFocus?.restore()
        val handled = super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN) tvFocus?.moved()
        return handled
    }
}
