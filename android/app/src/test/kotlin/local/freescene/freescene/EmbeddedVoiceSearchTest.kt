package local.freescene.freescene

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.content.pm.ServiceInfo
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSpeechRecognizer

private class EmbeddedResult : MethodChannel.Result {
    var calls = 0
    var text: Any? = null
    var code: String? = null
    override fun success(result: Any?) { calls++; text = result }
    override fun error(errorCode: String, message: String?, details: Any?) { calls++; code = errorCode }
    override fun notImplemented() { fail("Missing method") }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class EmbeddedVoiceSearchTest {
    private val audio = Manifest.permission.RECORD_AUDIO
    private val events = mutableListOf<Map<String, Any>>()
    private val activity get() = Robolectric.buildActivity(Activity::class.java).setup().get()
    private fun results(text: String) = Bundle().apply {
        putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(text))
    }
    private fun recorder() = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
    @Before fun recognitionService() {
        val app = RuntimeEnvironment.getApplication()
        shadowOf(app).grantPermissions(audio)
        val info = ResolveInfo().apply {
            serviceInfo = ServiceInfo().apply { packageName = "fixture"; name = "Recognizer"; exported = true }
        }
        shadowOf(app.packageManager).addResolveInfoForIntent(Intent(RecognitionService.SERVICE_INTERFACE), info)
        Settings.Secure.putString(app.contentResolver, "voice_recognition_service", "fixture/Recognizer")
    }

    @Test fun permissionThenDirectCaptureReturnsTextWithoutLaunchingSearchActivity() {
        val host = activity; val voice = EmbeddedVoiceSearch(host, events::add); val result = EmbeddedResult()
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
        voice.start("ru-RU", result)
        assertEquals(EmbeddedVoiceSearch.PERMISSION, shadowOf(host).lastRequestedPermission.requestCode)
        assertEquals("android.content.pm.action.REQUEST_PERMISSIONS", shadowOf(host).nextStartedActivityForResult.intent.action)
        voice.permissionResult(EmbeddedVoiceSearch.PERMISSION, arrayOf(audio), intArrayOf(PackageManager.PERMISSION_GRANTED))
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(shadowOf(host).nextStartedActivityForResult)
        val capture = recorder()
        assertEquals("ru-RU", capture.lastRecognizerIntent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
        assertTrue(capture.lastRecognizerIntent.getBooleanExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false))
        capture.triggerOnReadyForSpeech(Bundle())
        capture.triggerOnRmsChanged(6f)
        capture.triggerOnPartialResults(results("Гангстер"))
        capture.triggerOnEndOfSpeech()
        capture.triggerOnResults(results("  Гангстерленд  "))
        assertEquals("Гангстерленд", result.text); assertEquals(1, result.calls)
        assertTrue(capture.isDestroyed)
        assertTrue(events.any { it["phase"] == "listening" })
        assertTrue(events.any { it["level"] == .6f })
        assertTrue(events.any { it["partial"] == "Гангстер" })
        assertTrue(events.any { it["phase"] == "recognizing" })
        capture.triggerOnError(SpeechRecognizer.ERROR_CLIENT)
        assertEquals(1, result.calls)
    }

    @Test fun deniedPermissionNeverStartsRecorder() {
        val host = activity; val voice = EmbeddedVoiceSearch(host, events::add); val result = EmbeddedResult()
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
        voice.start(null, result)
        voice.permissionResult(EmbeddedVoiceSearch.PERMISSION, arrayOf(audio), intArrayOf(PackageManager.PERMISSION_DENIED))
        assertEquals("voice_permission", result.code); assertEquals(1, result.calls)
        assertNull(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
    }

    @Test fun permissionScreenMayCoverHostButBackgroundRecordingIsCancelled() {
        val voice = EmbeddedVoiceSearch(activity, events::add); val result = EmbeddedResult()
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
        voice.start(null, result); voice.hostStopped()
        assertEquals(0, result.calls)
        voice.permissionResult(EmbeddedVoiceSearch.PERMISSION, arrayOf(audio), intArrayOf(PackageManager.PERMISSION_GRANTED))
        shadowOf(Looper.getMainLooper()).idle()
        voice.hostStopped()
        assertEquals(1, result.calls); assertNull(result.text); assertTrue(recorder().isDestroyed)
    }

    @Test fun cancelPermissionIgnoresDelayedGrant() {
        val voice = EmbeddedVoiceSearch(activity, events::add); val result = EmbeddedResult()
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(audio)
        voice.start(null, result); voice.cancel()
        voice.permissionResult(EmbeddedVoiceSearch.PERMISSION, arrayOf(audio), intArrayOf(PackageManager.PERMISSION_GRANTED))
        assertEquals(1, result.calls); assertNull(result.text)
        assertNull(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
    }

    @Test fun noRecognitionServiceReturnsAnErrorWithoutOpeningAnotherActivity() {
        val host = activity
        shadowOf(host.packageManager).removeResolveInfosForIntent(Intent(RecognitionService.SERVICE_INTERFACE), "fixture")
        val result = EmbeddedResult(); EmbeddedVoiceSearch(host, events::add).start(null, result)
        assertEquals("voice_unavailable", result.code)
        assertNull(shadowOf(host).nextStartedActivityForResult)
    }

    @Test fun cancelReleasesMicrophoneAndLateResultsCannotOverwriteNextQuery() {
        val voice = EmbeddedVoiceSearch(activity, events::add); val first = EmbeddedResult()
        voice.start(null, first); shadowOf(Looper.getMainLooper()).idle()
        val old = recorder(); voice.cancel(); assertTrue(old.isDestroyed)
        val next = EmbeddedResult(); voice.start("en-US", next); shadowOf(Looper.getMainLooper()).idle()
        old.triggerOnResults(results("wrong")); old.triggerOnError(SpeechRecognizer.ERROR_AUDIO)
        assertEquals(1, first.calls); assertNull(first.text); assertEquals(0, next.calls)
        recorder().triggerOnResults(results("Dune")); assertEquals("Dune", next.text)
    }

    @Test fun noMatchCanRetryAndOnlyFinalTextIsSubmitted() {
        val voice = EmbeddedVoiceSearch(activity, events::add); val first = EmbeddedResult()
        voice.start(null, first); shadowOf(Looper.getMainLooper()).idle()
        recorder().triggerOnPartialResults(results("partial")); assertEquals(0, first.calls)
        recorder().triggerOnError(SpeechRecognizer.ERROR_NO_MATCH)
        assertEquals("voice_no_match", first.code); assertTrue(recorder().isDestroyed)
        val second = EmbeddedResult(); voice.start(null, second); shadowOf(Looper.getMainLooper()).idle()
        recorder().triggerOnResults(results("")); assertEquals("voice_no_match", second.code)
    }

    @Test fun duplicateTapDoesNotReplaceActiveRequestAndSilenceTimesOut() {
        val voice = EmbeddedVoiceSearch(activity, events::add); val first = EmbeddedResult(); val second = EmbeddedResult()
        voice.start(null, first); voice.start(null, second)
        assertEquals("busy", second.code); assertEquals(0, first.calls)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals("voice_timeout", first.code); assertTrue(recorder().isDestroyed)
        voice.cancel(); assertEquals(1, first.calls)
    }

    @Test fun stalledFinalResultHasShorterDeadlineAndNetworkErrorIsSpecific() {
        val voice = EmbeddedVoiceSearch(activity, events::add); val first = EmbeddedResult()
        voice.start(null, first); shadowOf(Looper.getMainLooper()).idle()
        recorder().triggerOnEndOfSpeech()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(11))
        assertEquals("voice_timeout", first.code)
        val second = EmbeddedResult(); voice.start(null, second); shadowOf(Looper.getMainLooper()).idle()
        recorder().triggerOnError(SpeechRecognizer.ERROR_NETWORK)
        assertEquals("voice_network", second.code); assertTrue(recorder().isDestroyed)
    }
}
