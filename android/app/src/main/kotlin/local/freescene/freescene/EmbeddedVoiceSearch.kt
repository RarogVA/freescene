package local.freescene.freescene

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel

/** TV capture uses the recognition service, never a second search Activity. */
class EmbeddedVoiceSearch(
    private val activity: Activity,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private var pending: MethodChannel.Result? = null
    private var recognizer: SpeechRecognizer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null
    private var generation = 0
    private var language = "ru-RU"

    fun start(language: String?, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Voice search is already active", null)
            return
        }
        pending = result
        generation++
        this.language = language ?: "ru-RU"
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            emit(mapOf("phase" to "permission"))
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION)
        } else launch()
    }

    fun permissionResult(request: Int, permissions: Array<out String>, grants: IntArray): Boolean {
        if (request != PERMISSION) return false
        if (pending == null) return true
        val index = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
        if (index >= 0 && grants.getOrNull(index) == PackageManager.PERMISSION_GRANTED) launch()
        else fail("voice_permission", "Microphone access denied")
        return true
    }

    private fun launch() {
        val attempt = generation
        fun active() = pending != null && generation == attempt
        try {
            if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
                fail("voice_unavailable", "No speech recognition service installed")
                return
            }
            emit(mapOf("phase" to "preparing"))
            val recorder = SpeechRecognizer.createSpeechRecognizer(activity)
            recognizer = recorder
            recorder.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    if (active()) emit(mapOf("phase" to "listening"))
                }
                override fun onBeginningOfSpeech() {
                    if (active()) emit(mapOf("phase" to "listening"))
                }
                override fun onRmsChanged(rmsdB: Float) {
                    if (active() && rmsdB.isFinite()) emit(mapOf("level" to (rmsdB / 10f).coerceIn(0f, 1f)))
                }
                override fun onPartialResults(results: Bundle?) {
                    if (active()) emit(mapOf("partial" to text(results).orEmpty()))
                }
                override fun onEndOfSpeech() {
                    if (active()) {
                        emit(mapOf("phase" to "recognizing"))
                        deadline(10_000)
                    }
                }
                override fun onResults(results: Bundle?) {
                    if (!active()) return
                    val value = text(results)
                    if (value == null) fail("voice_no_match", "No speech recognized")
                    else complete(value)
                }
                override fun onError(error: Int) {
                    if (!active()) return
                    val code = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "voice_permission"
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "voice_no_match"
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                        SpeechRecognizer.ERROR_SERVER -> "voice_network"
                        SpeechRecognizer.ERROR_AUDIO -> "voice_audio"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "voice_busy"
                        else -> "voice_unavailable"
                    }
                    fail(code, "Speech recognition error: $error")
                }
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
            })
            deadline(30_000)
            recorder.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1))
        } catch (_: SecurityException) {
            fail("voice_permission", "Microphone access denied")
        } catch (_: RuntimeException) {
            fail("voice_unavailable", "Speech recognition service unavailable")
        }
    }

    private fun text(bundle: Bundle?): String? = bundle
        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        ?.firstOrNull { it.isNotBlank() }?.trim()?.take(250)

    private fun deadline(millis: Long) {
        timeout?.let(handler::removeCallbacks)
        timeout = Runnable { fail("voice_timeout", "Speech recognition timed out") }
            .also { handler.postDelayed(it, millis) }
    }

    private fun release(): MethodChannel.Result? {
        val callback = pending
        pending = null
        generation++ // A destroyed service may still deliver callbacks.
        timeout?.let(handler::removeCallbacks)
        timeout = null
        val recorder = recognizer
        recognizer = null
        try { recorder?.cancel() } catch (_: RuntimeException) { }
        try { recorder?.destroy() } catch (_: RuntimeException) { }
        return callback
    }
    private fun complete(value: String?) { release()?.success(value) }
    private fun fail(code: String, message: String) { release()?.error(code, message, null) }
    fun cancel() { complete(null) }
    fun hostStopped() {
        // TV permission prompts can cover the host Activity. Let that request
        // complete, but never keep an actual recording alive in the background.
        if (recognizer != null) cancel()
    }
    companion object { const val PERMISSION = 403 }
}
