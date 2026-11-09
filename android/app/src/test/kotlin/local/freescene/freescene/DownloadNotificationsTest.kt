package local.freescene.freescene

import android.app.Activity
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DownloadNotificationsTest {
    private class Reply : MethodChannel.Result {
        var error: String? = null
        override fun success(value: Any?) {}
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() {}
    }
    @Test fun refusalContinuesActionAndIsNotRequestedAgain() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val permission = DownloadNotifications(activity); var calls = 0
        permission.run(Reply()) { calls++ }
        assertEquals(0, calls)
        assertEquals(DownloadNotifications.REQUEST, shadowOf(activity).lastRequestedPermission.requestCode)
        permission.complete(DownloadNotifications.REQUEST)
        assertEquals(1, calls)
        permission.run(Reply()) { calls++ }
        assertEquals(2, calls)
    }
    @Test fun destructionCancelsPendingActionWithoutLaunchingInstaller() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val permission = DownloadNotifications(activity); val reply = Reply(); var invoked = false
        permission.run(reply) { invoked = true }
        permission.cancel(); permission.complete(DownloadNotifications.REQUEST)
        assertEquals("cancelled", reply.error); assertFalse(invoked)
    }
}
