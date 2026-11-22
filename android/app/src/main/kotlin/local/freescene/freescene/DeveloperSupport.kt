package local.freescene.freescene

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

object DeveloperSupport {
    const val URL = "https://pay.cloudtips.ru/p/d45d5d02"

    fun open(activity: Activity, result: MethodChannel.Result) {
        try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(URL))
                .addCategory(Intent.CATEGORY_BROWSABLE))
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("browser_unavailable", "Could not open support page", null)
        } catch (_: SecurityException) {
            result.error("browser_unavailable", "Could not open support page", null)
        }
    }
}
