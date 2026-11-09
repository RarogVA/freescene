package local.freescene.freescene

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class UpdatePolicyTest {
    private fun release() = JSONObject().put("tag_name", "v1.2.9").put("draft", false).put("prerelease", false)
        .put("assets", JSONArray().put(JSONObject().put("name", "app-armeabi-v7a-tv-release.apk")
            .put("id", 42).put("state", "uploaded").put("size", 20000000)
            .put("url", "${UpdatePolicy.repository}/releases/assets/42").put("digest", "sha256:" + "a".repeat(64))))
    @Test fun versionsAreNumericAndOnlyStableUpgradeIsOffered() {
        assertTrue(UpdatePolicy.newer("v1.10.0", "1.9.9"))
        for (v in listOf("v1.2.8", "v1.2.7", "v1.2.9-beta", "junk", "v99999999.0.0")) assertFalse(v, UpdatePolicy.newer(v, "1.2.8"))
        assertNotNull(UpdatePolicy.asset(release(), "1.2.8", "tv", "armeabi-v7a"))
        assertNull(UpdatePolicy.asset(release(), "1.2.9", "tv", "armeabi-v7a"))
        assertNull(UpdatePolicy.asset(release().put("prerelease", true), "1.2.8", "tv", "armeabi-v7a"))
        assertNull(UpdatePolicy.asset(release().put("draft", true), "1.2.8", "tv", "armeabi-v7a"))
    }
    @Test fun requiresExactFlavorAbiBoundedSizeDigestAndRepository() {
        assertNull(UpdatePolicy.asset(release(), "1.2.8", "mobile", "armeabi-v7a"))
        assertNull(UpdatePolicy.asset(release(), "1.2.8", "tv", "arm64-v8a"))
        for ((key, value) in listOf("size" to 0L, "size" to UpdatePolicy.maxApk + 1,
            "digest" to "", "digest" to "sha256:bad", "state" to "new",
            "url" to "https://api.github.com/repos/other/app/releases/assets/42")) {
            val r = release(); r.getJSONArray("assets").getJSONObject(0).put(key, value)
            assertNull(key, UpdatePolicy.asset(r, "1.2.8", "tv", "armeabi-v7a"))
        }
    }
    @Test fun rejectsForeignRedirects() {
        assertTrue(UpdatePolicy.downloadHost("https://release-assets.githubusercontent.com/file?signature=example"))
        for (url in listOf("http://api.github.com/a", "https://api.github.com.evil.test/a", "https://user:password@github.com/a", "https://github.com:8080/a", "file:///tmp/a")) assertFalse(UpdatePolicy.downloadHost(url))
    }
}
