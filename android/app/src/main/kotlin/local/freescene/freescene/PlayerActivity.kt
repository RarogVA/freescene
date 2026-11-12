package local.freescene.freescene

import android.app.Activity
import android.app.AlertDialog
import android.os.Handler
import android.os.Looper
import android.widget.ImageButton
import android.widget.ArrayAdapter
import android.view.ViewGroup
import org.json.JSONObject
import android.app.ActivityManager
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.common.Tracks
import androidx.media3.common.Format
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

/** One platform-decoded player, released whenever the activity is stopped. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
open class PlayerActivity : Activity() {
    private var idleControls: TvIdleControls? = null
    private var tvFocus: TvPlayerFocus? = null
    private var controlsSuspended = false
    private val back = RemoteBack()
    private var backPressed = false
    private var backHidesControls = false
    override fun onResume() { super.onResume(); TvWindow.applyPlayer(this); if (resumeDialog == null) idleControls?.start() }
    override fun onPause() { watchedClock.sample(false); saveProgress(); idleControls?.stop(); super.onPause() }
    override fun onWindowFocusChanged(focused: Boolean) {
        super.onWindowFocusChanged(focused)
        if (focused) TvWindow.applyPlayer(this)
        if (focused && resumeDialog == null) idleControls?.start() else idleControls?.stop()
        if (focused) restoreTvFocus()
    }
    private lateinit var view: PlayerView
    private var settings: PlayerSettings? = null
    private lateinit var close: PlayerCloseButton
    private lateinit var scale: PlayerScaleControl
    private lateinit var status: TextView
    private lateinit var titleBar: PlayerTitleView
    private var player: ExoPlayer? = null
    private var position = 0L
    private var playing = true
    private val history by lazy { PlaybackHistory(this) }
    private val watchedClock = WatchedClock { WatchedHistory(this).set(intent.getStringExtra("watchedSource"), intent.getStringExtra("watchedTitle"), true) }
    private val watchTime = object : Runnable {
        override fun run() {
            if (stopped) return
            watchedClock.sample(player?.isPlaying == true)
            val waiting = !playbackFailed && (player == null || player?.playbackState == Player.STATE_BUFFERING || preparing)
            loadingTrack?.busy(waiting)
            if (waiting && !wasWaiting) view.showController()
            settings?.update()
            restoreTvFocus()
            wasWaiting = waiting
            handler.postDelayed(this, 500)
        }
    }
    private var playbackKey: String? = null
    private var playbackReady = false
    private var playbackFailed = false
    private var loadingTrack: PlayerLoadingTrack? = null
    private var wasWaiting = false
    private var resumeDialog: AlertDialog? = null
    private val handler = Handler(Looper.getMainLooper())
    private val savePlayback = object : Runnable {
        override fun run() {
            if (stopped) return
            saveProgress()
            handler.postDelayed(this, 5000)
        }
    }
    private val torrentId get() = intent.getStringExtra("torrentId")
    private var fileIndex = -1
    private var videos = emptyList<JSONObject>()
    private var chooser: AlertDialog? = null
    private var stopped = true
    private var preparing = false
    private var audioWarning: String? = null
    private lateinit var episodes: ImageButton
    protected open fun request(method: String, extra: JSONObject = JSONObject(), callback: (Result<JSONObject>) -> Unit = {}) {
        TorrentEngine.submit(this, extra.put("method", method).put("id", torrentId), callback)
    }
    private val poll = object : Runnable {
        override fun run() {
            if (stopped || torrentId == null) return
            request("status") { result ->
                if (stopped || isFinishing) return@request
                val tasks = result.getOrNull()?.optJSONArray("tasks")
                val task = (0 until (tasks?.length() ?: 0)).map { tasks!!.getJSONObject(it) }.find { it.optString("id") == torrentId }
                if (task == null) { playbackFailed = true; status.text = "Загрузка недоступна. Вернитесь и повторите." }
                else {
                    if (intent.getStringExtra("title").isNullOrBlank()) titleBar.text = task.optString("name", "FreeScene")
                    val files = task.optJSONArray("files")
                    videos = (0 until (files?.length() ?: 0)).map { files!!.getJSONObject(it) }.filter { it.optBoolean("video") }
                    updateEpisodeControls()
                    episodes.visibility = if (intent.getBooleanExtra("series", false) && videos.size > 1 && close.visibility == View.VISIBLE) View.VISIBLE else View.GONE
                    when {
                        task.optString("error").isNotBlank() -> { playbackFailed = true; status.text = task.optString("error") }
                        !task.optBoolean("metadata") -> status.text = "Получение списка файлов…"
                        videos.isEmpty() -> { playbackFailed = true; status.text = "В раздаче нет поддерживаемого видео" }
                        player?.playerError != null -> Unit // Keep the decoder error visible until retry/exit.
                        player == null && !preparing && chooser == null && resumeDialog == null -> {
                            if (fileIndex >= 0 || videos.size == 1) openFile(videos.find { it.optInt("index") == fileIndex } ?: videos.first(), reset = false)
                            else chooseEpisode()
                        }
                        player?.playbackState == Player.STATE_BUFFERING -> status.text = "Буферизация · ↓ ${task.optLong("rate") / 1024} КиБ/с · Сиды: ${task.optInt("seeds")} · Пиры: ${task.optInt("peers")}"
                        else -> status.text = audioWarning.orEmpty()
                    }
                }
                handler.postDelayed(this, 1000)
            }
        }
    }
    private fun chooseEpisode() {
        if (videos.isEmpty() || chooser != null) return
        val initialSelection = player == null
        suspendControls()
        val labels = videos.map { it.optString("name") }
        val adapter = object : ArrayAdapter<String>(this, android.R.layout.simple_list_item_single_choice, labels) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View = super.getView(position, convertView, parent).apply {
                (this as TextView).setTextColor(PlayerColors.text)
                maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
            }
        }
        val selected = videos.indexOfFirst { it.optInt("index") == fileIndex }.coerceAtLeast(0)
        chooser = AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Сезоны и серии")
            .setSingleChoiceItems(adapter, selected) { dialog, which -> dialog.dismiss(); openFile(videos[which]) }
            .setNegativeButton("Назад") { _, _ -> if (player == null) finish() }
            .create().also { dialog ->
                dialog.setOnCancelListener { if (player == null) finish() }
                dialog.setOnDismissListener { chooser = null; resumeControls(); if (TvWindow.isTv(this)) { if (initialSelection) view.findViewById<View>(androidx.media3.ui.R.id.exo_play_pause)?.requestFocus() else episodes.requestFocus() } }
                dialog.show()
                dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(PlayerColors.panel))
                dialog.listView.setSelection(selected)
                if (TvWindow.isTv(this)) dialog.listView.requestFocus()
            }
    }
    private fun openFile(file: JSONObject, reset: Boolean = true) {
        if (stopped || isFinishing) return
        preparing = true
        saveProgress()
        fileIndex = file.getInt("index")
        if (reset) { position = 0; playing = true }
        player?.release(); player = null; view.player = null; playbackReady = false
        status.text = "Буферизация…"
        request("stream", JSONObject().put("file", fileIndex)) { result ->
            preparing = false
            if (stopped || isFinishing) return@request
            result.onSuccess { playMedia(it.getString("url"), "torrent:$torrentId:$fileIndex") }
                .onFailure { playbackFailed = true; status.text = it.message ?: "Не удалось открыть файл" }
        }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        PlayerColors.restore(this)
        watchedClock.elapsed = state?.getLong("watchedElapsed") ?: 0
        if (!TorrentPolicy.id(torrentId) && !PlaybackPolicy.allowed(intent.getStringExtra("url"))) { finish(); return }
        position = state?.getLong("position") ?: 0
        fileIndex = state?.getInt("torrentFile", -1) ?: torrentId?.let { history.torrentFile(it) } ?: -1
        playing = state?.getBoolean("playing") ?: true
        playbackKey = state?.getString("playbackKey")
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        view = PlayerView(this).apply {
            setBackgroundColor(android.graphics.Color.BLACK)
            setShutterBackgroundColor(android.graphics.Color.BLACK)
            controllerShowTimeoutMs = if (TvWindow.isTv(this@PlayerActivity)) 0 else 4000
            setShowSubtitleButton(TvWindow.isTv(this@PlayerActivity))
            setShowPreviousButton(false)
            setShowNextButton(false)
            setControllerAnimationEnabled(false)
            if (TvWindow.isTv(this@PlayerActivity)) {
                controllerAutoShow = false
            }
        }
        settings = PlayerSettings(this, opened = { suspendControls() }, dismissed = { resumeControls() },
            scaling = { scale.button.performClick() }) {
            view.player
        }.also { it.bind(view) }
        close = PlayerCloseButton(this).apply {
            tag = "player-close"
            setOnClickListener { finish() }
        }
        scale = PlayerScaleControl(this, state?.getInt("scaleMode") ?: 0,
            opened = { suspendControls() },
            dismissed = { if (!stopped) { TvWindow.applyPlayer(this); resumeControls() } },
            changed = { applyScale(it) })
        applyScale(scale.mode)
        status = TextView(this).apply { setTextColor(android.graphics.Color.WHITE) }
        val root = FrameLayout(this).apply { setBackgroundColor(android.graphics.Color.BLACK) }
        root.isFocusableInTouchMode = TvWindow.isTv(this)
        root.addView(view, FrameLayout.LayoutParams(-1, -1))
        titleBar = PlayerTitleView(this, intent.getStringExtra("title")).apply {
            setBackgroundColor(android.graphics.Color.argb(210, 34, 36, 41))
            val inset = (72 * resources.displayMetrics.density).toInt()
            setPadding(inset, 0, (132 * resources.displayMetrics.density).toInt(), 0)
        }
        root.addView(titleBar, FrameLayout.LayoutParams(-1, (72 * resources.displayMetrics.density).toInt(), Gravity.TOP))
        root.addView(close, FrameLayout.LayoutParams(close.diameter, close.diameter, Gravity.TOP or Gravity.START).apply {
            val inset = (12 * resources.displayMetrics.density).toInt()
            setMargins(inset, inset, inset, inset)
        })
        root.addView(status, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply {
            val inset = (16 * resources.displayMetrics.density).toInt()
            setMargins(inset, 0, inset, (100 * resources.displayMetrics.density).toInt())
        })
        status.gravity = Gravity.START
        status.setTextColor(PlayerColors.text)
        status.setShadowLayer(3f, 0f, 1f, android.graphics.Color.BLACK)
        view.findViewById<androidx.media3.ui.DefaultTimeBar>(androidx.media3.ui.R.id.exo_progress)?.apply {
            setPlayedColor(PlayerColors.accent); setScrubberColor(PlayerColors.accent)
            if (TvWindow.isTv(this@PlayerActivity)) {
                setKeyTimeIncrement(10000)
                var lastRepeatTime: Long? = null
                setOnKeyListener { _, key, event ->
                    if (key != KeyEvent.KEYCODE_DPAD_LEFT && key != KeyEvent.KEYCODE_DPAD_RIGHT) false
                    else {
                        if (event.action == KeyEvent.ACTION_DOWN) {
                            val repeated = event.repeatCount > 0
                            if (!repeated) lastRepeatTime = null
                            // Remote repeat rates differ. Advance at most twice a
                            // second; grow the held step by a minute every 2 seconds.
                            if (!repeated || lastRepeatTime == null || event.eventTime - lastRepeatTime!! >= 500) {
                                val heldMs = (event.eventTime - event.downTime).coerceAtLeast(0)
                                val minutes = (1 + heldMs / 2000).coerceAtMost(5)
                                setKeyTimeIncrement(if (repeated) minutes * 60000 else 10000)
                                onKeyDown(key, event) // Preserve Media3's scrub preview and bounds.
                                setKeyTimeIncrement(10000) // Touch/accessibility never inherit acceleration.
                                if (repeated) lastRepeatTime = event.eventTime
                            }
                        } else if (event.action == KeyEvent.ACTION_UP) lastRepeatTime = null
                        true // Keep focus on the timeline at the start/end too.
                    }
                }
            }
            loadingTrack = PlayerLoadingTrack(this)
        }
        episodes = PlayerCloseButton(this).apply {
            contentDescription = "Сезоны и серии"
            setImageResource(android.R.drawable.ic_menu_sort_by_size)
            visibility = View.GONE
            setOnClickListener { chooseEpisode() }
        }
        root.addView(episodes, FrameLayout.LayoutParams(close.diameter, close.diameter, Gravity.TOP or Gravity.END).apply {
            val inset = (12 * resources.displayMetrics.density).toInt()
            setMargins(inset, inset, (72 * resources.displayMetrics.density).toInt(), inset)
        })
        root.addView(scale.button, FrameLayout.LayoutParams(close.diameter, close.diameter, Gravity.TOP or Gravity.END).apply {
            val inset = (12 * resources.displayMetrics.density).toInt()
            setMargins(inset, inset, inset, inset)
        })
        if (!TvWindow.isTv(this)) scale.button.visibility = View.GONE
        setContentView(root)
        fun styleControls(node: View) {
            if (node is ImageButton || node is android.widget.Button) {
                TvButtonFocus.apply(node, fill = android.graphics.Color.TRANSPARENT)
                if (node is ImageButton) node.imageTintList = android.content.res.ColorStateList.valueOf(PlayerColors.accent)
            }
            if (node is ViewGroup) for (i in 0 until node.childCount) styleControls(node.getChildAt(i))
        }
        styleControls(view)
        if (TvWindow.isTv(this)) {
            tvFocus = TvPlayerFocus(root) { view.findViewById<View>(androidx.media3.ui.R.id.exo_play_pause) }
            view.findViewById<View>(androidx.media3.ui.R.id.exo_play_pause)?.setOnClickListener {
                val current = player
                if (current != null) androidx.media3.common.util.Util.handlePlayPauseButtonAction(current)
                else { playing = !playing; prepareWaitingPlayButton() }
            }
        }
        view.setControllerVisibilityListener(PlayerView.ControllerVisibilityListener { visibility ->
            val visible = visibility == View.VISIBLE
            if (visible) settings?.update()
            titleBar.visibility = if (visible) View.VISIBLE else View.INVISIBLE
            close.visibility = titleBar.visibility
            scale.button.visibility = if (TvWindow.isTv(this)) titleBar.visibility else View.GONE
            episodes.visibility = if (visible && intent.getBooleanExtra("series", false) && videos.size > 1) View.VISIBLE else View.GONE
        })
        idleControls = TvIdleControls(TvWindow.isTv(this)) { visible ->
            if (visible) {
                view.showController()
                restoreTvFocus()
            } else {
                tvFocus?.remember()
                view.hideController()
                root.requestFocus()
            }
        }
        view.showController()
    }
    private fun prepareWaitingPlayButton() {
        if (!TvWindow.isTv(this) || player != null || !::view.isInitialized) return
        view.findViewById<ImageButton>(androidx.media3.ui.R.id.exo_play_pause)?.apply {
            isEnabled = true; alpha = 1f
            setImageResource(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
            contentDescription = getString(if (playing) androidx.media3.ui.R.string.exo_controls_pause_description
                else androidx.media3.ui.R.string.exo_controls_play_description)
        }
    }
    private fun restoreTvFocus() {
        settings?.update()
        if (stopped || controlsSuspended || resumeDialog != null || chooser != null || !hasWindowFocus() ||
            !::view.isInitialized || idleControls?.visible == false || !view.isControllerFullyVisible) return
        prepareWaitingPlayButton()
        tvFocus?.restore()
    }
    private fun suspendControls() {
        controlsSuspended = true
        idleControls?.stop()
        view.controllerShowTimeoutMs = 0
    }
    private fun resumeControls() {
        controlsSuspended = false
        if (stopped) return
        view.controllerShowTimeoutMs = if (TvWindow.isTv(this)) 0 else 4000
        view.showController()
        idleControls?.start()
        restoreTvFocus()
    }
    private fun applyScale(mode: Int) {
        view.resizeMode = when (mode) {
            1 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            2 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
    }
    override fun onStart() {
        super.onStart()
        stopped = false
        if (!isFinishing) startPlayer()
        handler.postDelayed(savePlayback, 5000)
        handler.post(watchTime)
    }
    protected open fun startPlayer() {
        if (torrentId != null) {
            status.text = "Получение списка файлов…"
            request("prepareStream") { result ->
                if (stopped || isFinishing) return@request
                result.onSuccess { startTorrentService(); handler.post(poll) }
                    .onFailure { playbackFailed = true; status.text = it.message ?: "Не удалось открыть раздачу" }
            }
        } else {
            val url = intent.getStringExtra("url")!!
            playMedia(url, intent.getStringExtra("playbackId") ?: "url:$url")
        }
    }
    private fun playMedia(url: String, key: String) {
        if (resumeDialog != null) return
        fun begin(at: Long) {
            if (stopped || isFinishing) return
            position = at
            playbackKey = key
            torrentId?.let { history.rememberTorrentFile(it, fileIndex) }
            startMedia(url)
        }
        if (playbackKey == key) { begin(position); return }
        val saved = history.read(key)
        if (saved == null) { begin(0); return }
        suspendControls()
        resumeDialog = PlaybackResumeDialog.show(this, saved.position,
            selected = { resume ->
                if (!resume) history.clear(key)
                begin(if (resume) saved.position else 0)
            },
            cancelled = { finish() },
            dismissed = { resumeDialog = null; resumeControls() })
    }
    private fun updateEpisodeControls() {
        val series = intent.getBooleanExtra("series", false) && videos.size > 1
        view.setShowPreviousButton(series)
        view.setShowNextButton(series)
        val index = videos.indexOfFirst { it.optInt("index") == fileIndex }
        for ((id, offset) in listOf(androidx.media3.ui.R.id.exo_prev to -1, androidx.media3.ui.R.id.exo_next to 1)) {
            view.findViewById<View>(id)?.apply {
                isEnabled = series && index >= 0 && index + offset in videos.indices
                alpha = if (isEnabled) 1f else .35f
                setOnClickListener { videos.getOrNull(index + offset)?.let { openFile(it, reset = true) } }
            }
        }
    }
    private fun saveProgress() {
        val current = player ?: return
        val key = playbackKey ?: return
        if (!playbackReady || current.isCurrentMediaItemLive) return
        history.save(key, current.currentPosition, current.duration.coerceAtLeast(0),
            current.playbackState == Player.STATE_ENDED)
    }
    protected open fun startTorrentService() { TorrentService.start(this) }
    protected open fun startMedia(url: String) {
        playbackFailed = false
        if (!PlaybackPolicy.allowed(url) && !TorrentEngine.trustedStream(url)) { status.text = "Недопустимый адрес видео"; return }
        val lowRam = (getSystemService(ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice
        val load = DefaultLoadControl.Builder().setTargetBufferBytes(PlaybackPolicy.bufferBytes(lowRam))
            .setBufferDurationsMs(10000, 30000, 1000, 2000)
            .setPrioritizeTimeOverSizeThresholds(false).build()
        val http = DefaultHttpDataSource.Factory().setReadTimeoutMs(60000).setConnectTimeoutMs(15000)
            .setUserAgent(PlaybackPolicy.userAgent(url) ?: "FreeScene/${BuildConfig.VERSION_NAME} Android")
        PlaybackPolicy.referrer(intent.getStringExtra("url"), intent.getStringExtra("referrer"))?.let {
            http.setDefaultRequestProperties(mapOf("Referer" to it))
        }
        audioWarning = null
        player = ExoPlayer.Builder(this, PlayerAudio.renderers(this)).setLoadControl(load)
            .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(this, http)))
            .setSeekBackIncrementMs(10000).setSeekForwardIncrementMs(10000).build().also {
                view.player = it
                if (lowRam) it.trackSelectionParameters = it.trackSelectionParameters.buildUpon()
                    .setMaxVideoSize(1920, 1080).build()
                it.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) { watchedClock.sample(isPlaying) }
                    override fun onTracksChanged(tracks: Tracks) {
                        audioWarning = PlayerAudio.warning(tracks, resources.configuration.locales[0].language == "ru")
                        if (it.playbackState == Player.STATE_READY && it.playerError == null)
                            status.text = audioWarning.orEmpty()
                    }
                    override fun onPlaybackStateChanged(state: Int) {
                        if (state == Player.STATE_READY) { playbackReady = true; playbackFailed = false }
                        if (state == Player.STATE_BUFFERING) status.text = if (resources.configuration.locales[0].language == "ru") "Буферизация…" else "Buffering…"
                        if (state == Player.STATE_ENDED) saveProgress()
                        if (state == Player.STATE_READY && it.playerError == null)
                            status.text = audioWarning.orEmpty()
                    }
                    override fun onPlayerError(error: PlaybackException) {
                        playbackFailed = true
                        loadingTrack?.stop()
                        status.text = if (resources.configuration.locales[0].language == "ru")
                            "Видео недоступно. Вернитесь и выберите другой источник."
                            else "Video unavailable. Go back and choose another source."
                        idleControls?.interact(); if (TvWindow.isTv(this@PlayerActivity)) close.requestFocus()
                    }
                })
                it.addAnalyticsListener(object : AnalyticsListener {
                    override fun onAudioDecoderInitialized(eventTime: AnalyticsListener.EventTime,
                        decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
                        android.util.Log.i("FreeSceneAudio", "Audio decoder: $decoderName")
                    }
                    override fun onAudioInputFormatChanged(eventTime: AnalyticsListener.EventTime,
                        format: Format, decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?) {
                        android.util.Log.i("FreeSceneAudio", "Audio format: ${format.sampleMimeType}, channels=${format.channelCount}, rate=${format.sampleRate}")
                    }
                })
                it.setMediaItem(if (torrentId != null) androidx.media3.common.MediaItem.fromUri(url)
                    else PlaybackPolicy.mediaItem(url, intent.getStringExtra("mimeType")))
                it.seekTo(position); it.prepare(); it.playWhenReady = playing
            }
    }
    override fun onStop() {
        watchedClock.sample(false)
        saveProgress()
        loadingTrack?.stop()
        stopped = true
        resumeDialog?.dismiss(); resumeDialog = null
        if (::scale.isInitialized) scale.dismiss()
        handler.removeCallbacksAndMessages(null)
        chooser?.dismiss(); chooser = null
        settings?.dismiss()
        if (torrentId != null) request("pause")
        idleControls?.stop()
        player?.let { position = it.currentPosition; playing = it.playWhenReady; it.release() }
        if (::view.isInitialized) view.player = null
        player = null
        playbackReady = false
        super.onStop()
    }
    override fun onDestroy() {
        if (torrentId != null && isFinishing && TvWindow.isTv(this)) request("closeStream")
        super.onDestroy()
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putInt("torrentFile", fileIndex)
        out.putLong("position", player?.currentPosition ?: position)
        out.putBoolean("playing", player?.playWhenReady ?: playing)
        out.putString("playbackKey", playbackKey)
        if (::scale.isInitialized) out.putInt("scaleMode", scale.mode)
        out.putLong("watchedElapsed", watchedClock.elapsed)
        super.onSaveInstanceState(out)
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0 && !backPressed) {
                backPressed = true
                // Latch at key-down: the idle timer may hide controls during a long press.
                backHidesControls = TvWindow.isTv(this) && ::view.isInitialized && view.isControllerFullyVisible
            }
            val handled = back.dispatch(event) {
                if (backHidesControls) {
                    idleControls?.hideNow()
                    view.hideController()
                } else finish()
            }
            if (event.action == KeyEvent.ACTION_UP) backPressed = false
            return handled
        }
        if (idleControls?.dispatch(event) == true) return true
        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_REWIND || event.keyCode == KeyEvent.KEYCODE_MEDIA_FAST_FORWARD) {
            if (event.action == KeyEvent.ACTION_DOWN) player?.let {
                it.seekTo(PlaybackPolicy.seek(it.currentPosition,
                    if (event.keyCode == KeyEvent.KEYCODE_MEDIA_REWIND) -10000 else 10000, it.duration))
            }
            return true
        }
        restoreTvFocus()
        val handled = super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode in listOf(
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN)) tvFocus?.moved()
        return handled
    }
}
