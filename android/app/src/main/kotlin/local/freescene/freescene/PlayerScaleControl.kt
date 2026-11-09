package local.freescene.freescene

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable

/** The same scale menu for decoded and embedded video, including D-pad focus. */
class PlayerScaleControl(
    activity: Activity,
    initialMode: Int,
    private val opened: () -> Unit,
    private val dismissed: () -> Unit,
    private val changed: (Int) -> Unit
) {
    var mode: Int = initialMode.takeIf { it in 0..2 } ?: 0
        private set
    private var dialog: AlertDialog? = null
    val button = PlayerCloseButton(activity).apply {
        tag = "player-scale"
        contentDescription = if (resources.configuration.locales[0].language == "ru") "Масштаб видео" else "Video scale"
        setImageResource(R.drawable.ic_player_scale)
        setOnClickListener {
            if (dialog != null) return@setOnClickListener
            opened()
            val ru = resources.configuration.locales[0].language == "ru"
            val labels = if (ru) arrayOf("Вписать", "Заполнить", "Растянуть") else arrayOf("Fit", "Fill", "Stretch")
            dialog = AlertDialog.Builder(activity, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle(contentDescription)
                .setSingleChoiceItems(labels, mode) { picker, index ->
                    mode = index; changed(index); picker.dismiss()
                }
                .setNegativeButton(if (ru) "Отмена" else "Cancel", null)
                .create().also { picker ->
                    picker.setOnDismissListener { dialog = null; if (TvWindow.isTv(activity)) requestFocus(); dismissed() }
                    picker.show()
                    picker.window?.setBackgroundDrawable(ColorDrawable(Color.rgb(25, 30, 38)))
                    picker.listView.setSelection(mode)
                    if (TvWindow.isTv(activity)) picker.listView.requestFocus()
                }
        }
    }
    fun dismiss() { dialog?.dismiss() }
}
