package local.freescene.freescene

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.view.View
import android.view.animation.LinearInterpolator

/** The same accent sweep as the desktop timeline; no animation while paused or failed. */
class PlayerLoadingTrack(private val host: View) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var fraction = 0f
    private var active = false
    private val motion = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1350; repeatCount = ValueAnimator.INFINITE; interpolator = LinearInterpolator()
        addUpdateListener { fraction = it.animatedValue as Float; invalidateSelf() }
    }
    init { host.overlay.add(this) }
    fun busy(value: Boolean) {
        setBounds(0, 0, host.width, host.height)
        if (active == value) return
        active = value
        if (value && ValueAnimator.areAnimatorsEnabled()) motion.start() else motion.cancel()
        invalidateSelf()
    }
    override fun draw(canvas: Canvas) {
        if (!active) return
        val inset = 6 * host.resources.displayMetrics.density
        val y = bounds.height() / 2f
        val radius = 2 * host.resources.displayMetrics.density
        val left = inset; val right = bounds.width() - inset
        if (right <= left) return
        paint.shader = null; paint.color = PlayerColors.accent; paint.alpha = 46
        canvas.drawRoundRect(left, y-radius, right, y+radius, radius, radius, paint)
        val width = right-left; val center = -width/2 + fraction*width*2
        paint.alpha = 255
        paint.shader = LinearGradient(center-width/2, 0f, center+width/2, 0f,
            intArrayOf(PlayerColors.accent and 0x00ffffff, PlayerColors.accent, PlayerColors.accent and 0x00ffffff),
            floatArrayOf(0f, .5f, 1f), Shader.TileMode.CLAMP)
        canvas.drawRoundRect(left, y-radius, right, y+radius, radius, radius, paint)
    }
    fun stop() { busy(false) }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(filter: ColorFilter?) {}
    @Deprecated("Deprecated in Java") override fun getOpacity() = PixelFormat.TRANSLUCENT
}
