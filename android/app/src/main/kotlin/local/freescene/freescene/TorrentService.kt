package local.freescene.freescene

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject

/** Android owns the download lifetime; the Flutter route does not. */
class TorrentService : Service() {
    companion object {
        private const val CHANNEL = "torrent-downloads"
        fun start(context: Context) {
            if (TvWindow.isTv(context)) return
            val intent = Intent(context, TorrentService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var stopped = false
    private val tick = object : Runnable {
        override fun run() {
            if (stopped) return
            TorrentEngine.submit(this@TorrentService, JSONObject().put("method", "status")) { result ->
                if (stopped) return@submit
                val tasks = result.getOrNull()?.optJSONArray("tasks")
                val active = (0 until (tasks?.length() ?: 0)).map { tasks!!.getJSONObject(it) }
                    .filter { it.optString("phase") !in setOf("paused", "failed", "completed") }
                if (active.isEmpty()) stopSelf()
                else {
                    val rate = active.sumOf { it.optLong("rate") } / 1024
                    getSystemService(NotificationManager::class.java).notify(51, notice("Загрузок: ${active.size} · ↓ $rate КиБ/с"))
                    handler.postDelayed(this, 2000)
                }
            }
        }
    }
    private fun notice(text: String): Notification {
        val launch = PendingIntent.getActivity(this, 51, Intent(this, MainActivity::class.java)
            .putExtra("downloads", true).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val pause = PendingIntent.getService(this, 52, Intent(this, TorrentService::class.java).setAction("pause"), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("FreeScene")
            .setContentText(text).setContentIntent(launch).setOngoing(true)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "Пауза", pause).build()).build()
    }
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, "Загрузки", NotificationManager.IMPORTANCE_LOW))
        startForeground(51, notice("Подготовка загрузки…"))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.removeCallbacks(tick)
        if (intent?.action == "pause") TorrentEngine.pauseAll(this) { stopSelf(startId) }
        else handler.postDelayed(tick, 2500)
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { TorrentEngine.pauseAll(this) { stopSelf(startId) } }
    override fun onDestroy() { stopped = true; handler.removeCallbacksAndMessages(null); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
