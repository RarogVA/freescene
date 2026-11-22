package local.freescene.freescene

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

class NoSupportBrowserActivity : Activity() {
    override fun startActivity(intent: Intent) { throw ActivityNotFoundException() }
}

private class SupportResult : MethodChannel.Result {
    var calls = 0
    var code: String? = null
    override fun success(result: Any?) { calls++ }
    override fun error(errorCode: String, message: String?, details: Any?) { calls++; code = errorCode }
    override fun notImplemented() { fail("Unexpected missing support method") }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class DeveloperSupportTest {
    @Test fun launchesExternalBrowserAtTheApprovedPaymentAddress() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val result = SupportResult()
        DeveloperSupport.open(controller.get(), result)
        val intent = shadowOf(controller.get()).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertTrue(intent.hasCategory(Intent.CATEGORY_BROWSABLE))
        assertEquals("https://pay.cloudtips.ru/p/d45d5d02", intent.dataString)
        assertNull(intent.component)
        assertEquals(1, result.calls)
        assertNull(result.code)
        controller.pause().stop().destroy()
    }

    @Test fun missingBrowserReturnsAnErrorForTheCopyLinkFallback() {
        val controller = Robolectric.buildActivity(NoSupportBrowserActivity::class.java).setup()
        val result = SupportResult()
        DeveloperSupport.open(controller.get(), result)
        assertEquals("browser_unavailable", result.code)
        assertEquals(1, result.calls)
        controller.pause().stop().destroy()
    }
}
