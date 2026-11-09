package local.freescene.freescene

import android.app.Activity
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import org.robolectric.Shadows.shadowOf

/** Dispatch a real pointer sequence; performClick would miss focus-only first taps. */
internal fun tapPlayerControl(activity: Activity, view: View) {
    val location = IntArray(2)
    view.getLocationOnScreen(location)
    val now = SystemClock.uptimeMillis()
    for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
        val event = MotionEvent.obtain(now, now, action,
            location[0] + view.width / 2f, location[1] + view.height / 2f, 0)
        try { activity.dispatchTouchEvent(event) } finally { event.recycle() }
    }
    shadowOf(Looper.getMainLooper()).idle()
}
