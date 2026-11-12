package local.freescene.freescene

import android.app.Activity
import android.app.AlertDialog
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

/** Menus use the media element's available tracks, never provider page URLs. */
internal class WebPlayerSettings(
    private val activity: Activity,
    private val send: (JSONObject) -> Unit,
    private val opened: () -> Unit,
    private val dismissed: () -> Unit,
    private val scaling: () -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private var dialog: AlertDialog? = null
    private var pending: String? = null
    private val ru get() = activity.resources.configuration.locales[0].language == "ru"
    private fun text(ru: String, en: String) = if (this.ru) ru else en
    private fun title(kind: String) = when (kind) {
        "audio" -> text("Аудио", "Audio")
        "text" -> text("Субтитры", "Subtitles")
        else -> text("Скорость", "Speed")
    }
    private fun show(builder: AlertDialog.Builder) {
        dialog?.dismiss()
        opened()
        dialog = builder.setNegativeButton(text("Отмена", "Cancel"), null).create().also { next ->
            next.setOnDismissListener { if (dialog === next) { dialog = null; dismissed() } }
            next.show()
            if (TvWindow.isTv(activity)) next.listView?.requestFocus()
        }
    }
    fun menu() {
        val kinds = listOf("audio", "speed", "text", "scale")
        show(AlertDialog.Builder(activity).setTitle(text("Настройки", "Settings"))
            .setItems((kinds.take(3).map(::title) + text("Масштаб видео", "Video scale")).toTypedArray()) { _, i ->
                dismiss()
                if (kinds[i] == "scale") scaling() else request(kinds[i])
            })
    }
    fun request(kind: String) {
        pending = kind
        opened()
        send(JSONObject().put("action", "settings"))
        main.postDelayed({
            if (pending == kind) { pending = null; unavailable(kind) }
        }, 3000)
    }
    private fun unavailable(kind: String) = show(AlertDialog.Builder(activity).setTitle(title(kind))
        .setMessage(text("Плеер не предоставил доступ к этой настройке.", "This setting is unavailable in the current player.")))

    fun received(data: JSONObject) {
        val kind = pending ?: return
        pending = null; main.removeCallbacksAndMessages(null)
        if (kind == "speed") {
            val speeds = listOf(.25, .5, .75, 1.0, 1.25, 1.5, 2.0)
            val selected = speeds.indexOf(data.optDouble("speed", 1.0))
            show(AlertDialog.Builder(activity).setTitle(title(kind))
                .setSingleChoiceItems(speeds.map { "${it}×" }.toTypedArray(), selected) { d, i ->
                    send(JSONObject().put("action", "speed").put("value", speeds[i])); d.dismiss()
                })
            return
        }
        val tracks = data.optJSONArray(kind)
        if (tracks == null || tracks.length() == 0 || tracks.length() > 32 || (0 until tracks.length()).any { tracks.optJSONObject(it) == null }) { unavailable(kind); return }
        val labels = (0 until tracks.length()).map { i ->
            tracks.getJSONObject(i).optString("label").take(128).ifBlank { "${title(kind)} ${i + 1}" }
        }.toMutableList()
        var selected = (0 until tracks.length()).firstOrNull { tracks.getJSONObject(it).optBoolean("selected") } ?: -1
        val offset = if (kind == "text") 1 else 0
        if (offset == 1) { labels.add(0, text("Выключены", "Off")); selected++ }
        show(AlertDialog.Builder(activity).setTitle(title(kind))
            .setSingleChoiceItems(labels.toTypedArray(), selected) { d, i ->
                send(JSONObject().put("action", kind).put("value", i - offset)); d.dismiss()
            })
    }
    fun dismiss() {
        pending = null; main.removeCallbacksAndMessages(null)
        dialog?.dismiss(); dialog = null
    }
}
