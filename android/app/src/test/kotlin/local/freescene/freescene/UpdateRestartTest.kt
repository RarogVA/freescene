package local.freescene.freescene

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class UpdateRestartTest {
    private val app: Context get() = RuntimeEnvironment.getApplication()
    private fun current(): Long = app.packageManager.getPackageInfo(app.packageName, 0).longVersionCode
    @Test fun handOffSurvivesNewReceiverAndIsConsumedOnlyOnce() {
        UpdateRestart.arm(app, current())
        UpdateRestartReceiver().onReceive(app, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))
        assertEquals(MainActivity::class.java.name, shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity.component!!.className)
        assertFalse(UpdateRestart.consume(app))
    }
    @Test fun cancellationWrongVersionExpiredAndUnrequestedInstallsDoNotLaunch() {
        assertFalse(UpdateRestart.consume(app))
        UpdateRestart.arm(app, current() + 1); assertFalse(UpdateRestart.consume(app))
        UpdateRestart.arm(app, current(), 1000); assertFalse(UpdateRestart.consume(app, 1000 + 2 * 24 * 60 * 60 * 1000L))
        UpdateRestart.arm(app, current()); UpdateRestart.cancel(app); assertFalse(UpdateRestart.consume(app))
    }
    @Test fun unrelatedBroadcastCannotConsumePendingUpdate() {
        UpdateRestart.arm(app, current())
        UpdateRestartReceiver().onReceive(app, Intent(Intent.ACTION_PACKAGE_ADDED))
        assertTrue(UpdateRestart.consume(app))
    }
    @Suppress("DEPRECATION")
    @Test fun migrationFrom1210RequiresMatchingPrivateApkSignatureAndBuild() {
        val apk = File(app.cacheDir, "updates/update.apk").apply { parentFile!!.mkdirs(); writeText("fixture") }
        val current = app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_SIGNATURES)
        current.signatures = arrayOf(Signature("012345"))
        shadowOf(app.packageManager).installPackage(current)
        val incoming = PackageInfo().apply { packageName = app.packageName; longVersionCode = current.longVersionCode; signatures = current.signatures }
        shadowOf(app.packageManager).setPackageArchiveInfo(apk.path, incoming)
        assertTrue(UpdateRestart.consume(app)); assertFalse(apk.exists()); assertFalse(UpdateRestart.consume(app))
        apk.writeText("fixture"); incoming.signatures = arrayOf(Signature("987654"))
        shadowOf(app.packageManager).setPackageArchiveInfo(apk.path, incoming)
        assertFalse(UpdateRestart.consume(app))
    }
}
