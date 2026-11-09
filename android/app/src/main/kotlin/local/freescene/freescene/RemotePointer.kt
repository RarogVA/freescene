package local.freescene.freescene

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.os.SystemClock

/** D-pad access to controls inside cross-origin players, without a JS bridge. */
class RemotePointer(context: Context, private val target: () -> View?) : View(context) {
    var cursorX = 0f; private set
    var cursorY = 0f; private set
    var returnToToolbar: (() -> Unit)? = null
    var cursorVisible = true
        set(value) { field = value; invalidate() }
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG)
    init {
        isFocusable = true; isFocusableInTouchMode = true
        contentDescription = "Video controls: arrows move, OK clicks, Back closes"
        setOnFocusChangeListener { _, _ -> invalidate() }
    }
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        cursorX = w / 2f; cursorY = h / 2f
    }
    override fun onDraw(canvas: Canvas) {
        if (!hasFocus() || !cursorVisible) return
        ink.style = Paint.Style.FILL; ink.color = PlayerColors.text
        canvas.drawCircle(cursorX, cursorY, 8 * resources.displayMetrics.density, ink)
        ink.style = Paint.Style.STROKE; ink.color = PlayerColors.onAccent; ink.strokeWidth = 2 * resources.displayMetrics.density
        canvas.drawCircle(cursorX, cursorY, 8 * resources.displayMetrics.density, ink)
    }
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val step = (18 + event.repeatCount.coerceAtMost(8) * 6) * resources.displayMetrics.density
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> cursorX = (cursorX - step).coerceAtLeast(1f)
            KeyEvent.KEYCODE_DPAD_RIGHT -> cursorX = (cursorX + step).coerceAtMost((width - 1).coerceAtLeast(1).toFloat())
            KeyEvent.KEYCODE_DPAD_UP -> if (cursorY <= step) { returnToToolbar?.invoke(); return true } else cursorY -= step
            KeyEvent.KEYCODE_DPAD_DOWN -> cursorY = (cursorY + step).coerceAtMost((height - 1).coerceAtLeast(1).toFloat())
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A -> {
                if (event.repeatCount == 0) performClick()
            }
            else -> return super.onKeyDown(keyCode, event)
        }
        invalidate(); return true
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean =
        if (keyCode in listOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A)) true
        else super.onKeyUp(keyCode, event)

    override fun performClick(): Boolean {
        super.performClick()
        val view = target() ?: return false
        val time = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(time, time, action, cursorX, cursorY, 0)
            try { view.dispatchTouchEvent(event) } finally { event.recycle() }
        }
        requestFocus(); return true
    }
}
