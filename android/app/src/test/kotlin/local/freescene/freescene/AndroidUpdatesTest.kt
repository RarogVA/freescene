package local.freescene.freescene

import android.content.Context
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.io.ByteArrayInputStream
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import android.os.Looper
import org.json.JSONObject
import org.json.JSONArray

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class AndroidUpdatesTest {
    @Suppress("DEPRECATION")
    @Test fun selfUpdatePreservesSystemDoneAndOpenScreenAfterCallerDies() {
        val uri = android.net.Uri.parse("content://local.freescene.freescene.tv.updates/updates/update.apk")
        val intent = UpdatePolicy.installerIntent(uri)
        assertEquals(android.content.Intent.ACTION_INSTALL_PACKAGE, intent.action)
        assertEquals(uri, intent.data)
        assertEquals("application/vnd.android.package-archive", intent.type)
        assertTrue(intent.flags and android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertFalse(intent.getBooleanExtra(android.content.Intent.EXTRA_RETURN_RESULT, false))
        assertFalse(intent.hasExtra(android.content.Intent.EXTRA_RETURN_RESULT))
    }
    private class Reply : MethodChannel.Result {
        @Volatile var done = false
        var value: Any? = null; var error: String? = null
        override fun success(result: Any?) { value = result; done = true }
        override fun error(code: String, message: String?, details: Any?) { error = code; done = true }
        override fun notImplemented() { error = "unsupported"; done = true }
        fun await(): Reply {
            val deadline = System.nanoTime() + 3000000000L
            while (!done && System.nanoTime() < deadline) { shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(5) }
            assertTrue("Worker did not complete", done); return this
        }
    }
    private class Connection(url: String, val code: Int, val content: ByteArray, val location: String? = null) : HttpURLConnection(URL(url)) {
        override fun connect() {}
        override fun disconnect() {}
        override fun usingProxy() = false
        override fun getResponseCode() = code
        override fun getInputStream() = ByteArrayInputStream(content)
        override fun getHeaderField(name: String?) = if (name == "Location") location else null
    }
    private fun call(client: AndroidUpdates, method: String): Reply = Reply().also { client.request(method, it) }.await()
    @Test fun checkUsesPublicRepositoryWithoutAccountOrAuthorizationHeader() {
        val app: Context = RuntimeEnvironment.getApplication()
        val connections = mutableListOf<Connection>()
        val client = AndroidUpdates(app) { url ->
            Connection(url, 200, "[]".toByteArray()).also(connections::add)
        }
        assertEquals(false, (call(client, "updateCheck").value as Map<*, *>)["available"])
        assertEquals(1, connections.size)
        assertEquals("https://api.github.com/repos/RarogVA/freescene/releases?per_page=20", connections.single().url.toString())
        assertNull(connections.single().getRequestProperty("Authorization"))
        val rejected = AndroidUpdates(app) { url -> Connection(url, 403, byteArrayOf()) }
        assertEquals("github_access", call(rejected, "updateCheck").error)
    }
    @Test fun anonymousDownloadRejectsWrongHashAndNeverSendsCredentials() {
        val app: Context = RuntimeEnvironment.getApplication()
        val abi = if (android.os.Build.SUPPORTED_ABIS.contains("arm64-v8a")) "arm64-v8a" else "armeabi-v7a"
        val release = JSONObject().put("tag_name", "v99.0.0").put("assets", JSONArray().put(JSONObject()
            .put("name", "app-$abi-${BuildConfig.FLAVOR}-release.apk").put("state", "uploaded")
            .put("id", 1).put("url", "${UpdatePolicy.repository}/releases/assets/1")
            .put("size", 3).put("digest", "sha256:" + "a".repeat(64))))
        val connections = mutableListOf<Connection>()
        val client = AndroidUpdates(app) { url ->
            val c = when {
                url.contains("?per_page") -> Connection(url, 200, JSONArray().put(release).toString().toByteArray())
                url.startsWith(UpdatePolicy.repository) -> Connection(url, 302, byteArrayOf(), "https://release-assets.githubusercontent.com/file")
                else -> Connection(url, 200, byteArrayOf(1, 2, 3))
            }
            connections.add(c); c
        }
        assertEquals(true, (call(client, "updateCheck").value as Map<*, *>)["available"])
        assertEquals("invalid_apk", call(client, "updateDownload").error)
        assertTrue(connections.all { it.getRequestProperty("Authorization") == null })
        assertNull(connections[2].getRequestProperty("Authorization"))
        assertFalse(java.io.File(app.cacheDir, "updates/download.part").exists())
        assertFalse(java.io.File(app.cacheDir, "updates/update.apk").exists())
    }
}
