package local.freescene.freescene

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognizerIntent
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

class NoVoiceActivity : Activity() {
    @Deprecated("Fixture")
    override fun startActivityForResult(intent: Intent, code: Int) { throw ActivityNotFoundException() }
}
private class VoiceResult : MethodChannel.Result {
    var calls = 0
    var value: Any? = null
    var code: String? = null
    override fun success(result: Any?) { calls++; value = result }
    override fun error(errorCode: String, message: String?, details: Any?) { calls++; code = errorCode }
    override fun notImplemented() { fail("Unexpected missing channel method") }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class VoiceSearchTest {
    private val audio = Manifest.permission.RECORD_AUDIO
    @Test fun mergedManifestRequestsMicrophoneButDoesNotRequireBuiltInHardware() {
        val app = RuntimeEnvironment.getApplication()
        val info = app.packageManager.getPackageInfo(app.packageName,
            PackageManager.GET_PERMISSIONS or PackageManager.GET_CONFIGURATIONS)
        assertTrue(info.requestedPermissions.orEmpty().contains(audio))
        val microphone = info.reqFeatures.orEmpty().single { it.name == PackageManager.FEATURE_MICROPHONE }
        assertEquals(0, microphone.flags and android.content.pm.FeatureInfo.FLAG_REQUIRED)
    }

    @Test fun firstTapRequestsPermissionThenLaunchesSystemUiAndReturnsTextOnce() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get(); val voice = VoiceSearch(activity); val result = VoiceResult()
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
        voice.start("ru-RU", result)
        val permission = shadowOf(activity).lastRequestedPermission
        assertEquals(VoiceSearch.PERMISSION, permission.requestCode)
        assertArrayEquals(arrayOf(audio), permission.requestedPermissions)
        assertEquals("android.content.pm.action.REQUEST_PERMISSIONS",
            shadowOf(activity).nextStartedActivityForResult.intent.action)
        assertNull(shadowOf(activity).nextStartedActivityForResult)
        assertEquals(0, result.calls)
        voice.permissionResult(VoiceSearch.PERMISSION, arrayOf(audio), intArrayOf(PackageManager.PERMISSION_GRANTED))
        val started = shadowOf(activity).nextStartedActivityForResult
        assertEquals(VoiceSearch.SPEECH, started.requestCode)
        assertEquals(RecognizerIntent.ACTION_RECOGNIZE_SPEECH, started.intent.action)
        assertEquals("ru-RU", started.intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
        assertEquals(RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            started.intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL))
        val data = Intent().putStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS, arrayListOf("  Test title  "))
        voice.activityResult(VoiceSearch.SPEECH, Activity.RESULT_OK, data)
        voice.activityResult(VoiceSearch.SPEECH, Activity.RESULT_OK, data)
        assertEquals(1, result.calls); assertEquals("Test title", result.value)
        controller.pause().stop().destroy()
    }

    @Test fun storedGrantSkipsPermissionRequestAndCancelDoesNotSubmitAQuery() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get(); val voice = VoiceSearch(activity); val result = VoiceResult()
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(audio)
        voice.start("en-US", result)
        assertNull(shadowOf(activity).lastRequestedPermission)
        assertNotNull(shadowOf(activity).nextStartedActivityForResult)
        voice.activityResult(VoiceSearch.SPEECH, Activity.RESULT_CANCELED, null)
        assertEquals(1, result.calls); assertNull(result.value); assertNull(result.code)
        controller.pause().stop().destroy()
    }

    @Test fun deniedOrDismissedPermissionReturnsRecoverableErrorWithoutStartingRecorder() {
        for (grants in listOf(intArrayOf(PackageManager.PERMISSION_DENIED), intArrayOf())) {
            val controller = Robolectric.buildActivity(Activity::class.java).setup()
            val activity = controller.get(); val voice = VoiceSearch(activity)
            shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
            val result = VoiceResult(); voice.start(null, result)
            assertEquals("android.content.pm.action.REQUEST_PERMISSIONS",
                shadowOf(activity).nextStartedActivityForResult.intent.action)
            voice.permissionResult(VoiceSearch.PERMISSION, arrayOf(audio), grants)
            assertEquals("voice_permission", result.code); assertEquals(1, result.calls)
            assertNull(shadowOf(activity).nextStartedActivityForResult)
            controller.pause().stop().destroy()
        }
    }

    @Test fun missingRecognizerReturnsErrorAndDestructionCancelsPendingPermission() {
        val controller = Robolectric.buildActivity(NoVoiceActivity::class.java).setup()
        val voice = VoiceSearch(controller.get()); val missing = VoiceResult()
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(audio)
        voice.start(null, missing); assertEquals("voice_unavailable", missing.code)
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
        val pending = VoiceResult(); voice.start(null, pending)
        val duplicate = VoiceResult(); voice.start(null, duplicate)
        assertEquals("busy", duplicate.code)
        voice.cancel()
        voice.permissionResult(VoiceSearch.PERMISSION, arrayOf(audio), intArrayOf(PackageManager.PERMISSION_GRANTED))
        assertEquals(1, pending.calls); assertNull(pending.value); assertNull(pending.code)
        controller.pause().stop().destroy()
    }
}
