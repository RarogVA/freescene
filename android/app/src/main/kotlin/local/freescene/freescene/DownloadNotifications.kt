package local.freescene.freescene

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/** Ask once when downloads/installation first need a visible notification. */
class DownloadNotifications(private val activity: Activity) {
    companion object { const val REQUEST = 645 }
    private var action: (() -> Unit)? = null
    private var result: MethodChannel.Result? = null
    private val preferences get() = activity.getSharedPreferences("notification-access", Context.MODE_PRIVATE)
    fun run(reply: MethodChannel.Result, ready: () -> Unit) {
        if (action != null) { reply.error("busy", "Permission request in progress", null); return }
        if (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED ||
            preferences.getBoolean("asked", false)) { ready(); return }
        action = ready; result = reply
        try { activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST) }
        catch (_: Exception) { complete(REQUEST) }
    }
    fun complete(code: Int) {
        if (code != REQUEST) return
        preferences.edit().putBoolean("asked", true).apply()
        val ready = action; action = null; result = null
        // A refusal must not prevent an explicit download or system install.
        ready?.invoke()
    }
    fun cancel() { action = null; result?.error("cancelled", "Activity closed", null); result = null }
}
