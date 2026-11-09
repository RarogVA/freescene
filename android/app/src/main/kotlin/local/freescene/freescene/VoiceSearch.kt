package local.freescene.freescene

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognizerIntent
import io.flutter.plugin.common.MethodChannel

/** Requests microphone access on demand, then delegates capture to Android's UI. */
class VoiceSearch(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var language = "ru-RU"

    fun start(language: String?, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "Voice search is already active", null); return }
        pending = result
        this.language = language ?: "ru-RU"
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
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

    @Suppress("DEPRECATION")
    private fun launch() {
        try {
            activity.startActivityForResult(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1), SPEECH)
        } catch (_: ActivityNotFoundException) {
            fail("voice_unavailable", "No speech recognition app")
        } catch (_: SecurityException) {
            fail("voice_permission", "Speech recognition permission denied")
        }
    }

    fun activityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != SPEECH) return false
        val callback = pending; pending = null
        callback?.success(if (result == Activity.RESULT_OK)
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.trim()
            else null)
        return true
    }
    private fun fail(code: String, message: String) {
        val callback = pending; pending = null
        callback?.error(code, message, null)
    }
    fun cancel() { val callback = pending; pending = null; callback?.success(null) }
    companion object { const val SPEECH = 401; const val PERMISSION = 402 }
}
