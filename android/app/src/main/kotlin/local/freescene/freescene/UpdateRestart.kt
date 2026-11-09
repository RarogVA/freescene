package local.freescene.freescene

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File

/** Durable hand-off: the process which starts the installer will be killed. */
object UpdateRestart {
    private const val NOTICE = 61
    private const val MAX_AGE = 24 * 60 * 60 * 1000L
    private fun prefs(context: Context) = context.getSharedPreferences("update-restart", Context.MODE_PRIVATE)
    fun arm(context: Context, version: Long, now: Long = System.currentTimeMillis()) {
        check(prefs(context).edit().putLong("target", version).putLong("at", now).commit())
    }
    fun cancel(context: Context) { prefs(context).edit().clear().commit() }
    @Suppress("DEPRECATION")
    private fun code(info: android.content.pm.PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    internal fun consume(context: Context, now: Long = System.currentTimeMillis()): Boolean {
        val saved = prefs(context)
        val current = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
        val target = saved.getLong("target", 0)
        val age = now - saved.getLong("at", 0)
        // 1.2.10 did not write a hand-off marker. Its private, recently downloaded
        // APK is a migration proof only when it is exactly the installed build.
        val apk = File(context.cacheDir, "updates/update.apk")
        val legacy = if (target == 0L && apk.isFile && now - apk.lastModified() in 0..MAX_AGE) {
            val incoming = context.packageManager.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNATURES)
            incoming != null && incoming.packageName == context.packageName && code(incoming) == code(current) &&
                !current.signatures.isNullOrEmpty() && incoming.signatures?.map { it.toCharsString() }?.toSet() == current.signatures!!.map { it.toCharsString() }.toSet()
        } else false
        val eligible = target == code(current) && age in 0..MAX_AGE || legacy
        cancel(context)
        if (eligible) {
            apk.delete()
            saved.edit().putBoolean("awaitingLaunch", true).commit()
        }
        return eligible
    }
    fun resumed(context: Context) {
        prefs(context).edit().remove("awaitingLaunch").apply()
        context.getSystemService(NotificationManager::class.java).cancel(NOTICE)
    }
    fun launch(context: Context) {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        runCatching { context.startActivity(intent) }
        // AOSP can silently deny a background activity launch on newer Android.
        // Keep a user-tappable fallback instead of retrying or requiring overlays.
        Handler(Looper.getMainLooper()).postDelayed({
            if (!prefs(context).getBoolean("awaitingLaunch", false)) return@postDelayed
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel("app-update", "Обновление FreeScene", NotificationManager.IMPORTANCE_DEFAULT))
            val open = PendingIntent.getActivity(context, NOTICE, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, "app-update") else Notification.Builder(context)
            runCatching { manager.notify(NOTICE, builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("FreeScene обновлён").setContentText("Открыть приложение")
                .setContentIntent(open).setAutoCancel(true).build()) }
        }, 2000)
    }
}

class UpdateRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED && UpdateRestart.consume(context)) {
            val pending = goAsync()
            UpdateRestart.launch(context)
            Handler(Looper.getMainLooper()).postDelayed({ pending?.finish() }, 2500)
        }
    }
}
