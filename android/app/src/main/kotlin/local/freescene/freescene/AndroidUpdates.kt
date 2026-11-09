package local.freescene.freescene

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

class UpdateFailure(val reason: String) : Exception(reason)

object UpdatePolicy {
    const val repository = "https://api.github.com/repos/RarogVA/freescene"
    const val maxApk = 128L * 1024 * 1024
    @Suppress("DEPRECATION")
    fun installerIntent(uri: Uri): Intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
        .setDataAndType(uri, "application/vnd.android.package-archive")
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    // Do not request EXTRA_RETURN_RESULT: PackageInstaller then suppresses its
    // Done/Open screen, but the caller is killed while replacing its own APK.
    fun newer(candidate: String, installed: String): Boolean {
        fun parts(value: String) = Regex("^v?(\\d{1,6})\\.(\\d{1,6})\\.(\\d{1,6})$").matchEntire(value)?.groupValues?.drop(1)?.map(String::toInt)
        val next = parts(candidate) ?: return false; val current = parts(installed) ?: return false
        return next.zip(current).firstOrNull { it.first != it.second }?.let { it.first > it.second } ?: false
    }
    fun asset(release: JSONObject, installed: String, flavor: String, abi: String): JSONObject? {
        if (release.optBoolean("draft") || release.optBoolean("prerelease") || !newer(release.optString("tag_name"), installed)) return null
        val assets = release.optJSONArray("assets") ?: return null
        for (i in 0 until assets.length()) {
            val item = assets.getJSONObject(i)
            if (item.optString("name") != "app-$abi-$flavor-release.apk" || item.optString("state") != "uploaded") continue
            val id = item.optLong("id")
            if (id <= 0 || item.optLong("size") !in 1..maxApk || item.optString("url") != "$repository/releases/assets/$id") continue
            if (!Regex("sha256:[a-f0-9]{64}").matches(item.optString("digest"))) continue
            return JSONObject(item.toString()).put("version", release.getString("tag_name").removePrefix("v"))
        }
        return null
    }
    fun downloadHost(value: String): Boolean = try {
        val uri = java.net.URI(value)
        uri.scheme == "https" && uri.rawUserInfo == null && uri.port in listOf(-1, 443) &&
            uri.host in setOf("api.github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "github.com")
    } catch (_: Exception) { false }
}

/** Anonymous updates from the fixed public repository, with verified APK identity. */
class AndroidUpdates(context: Context,
    private val openConnection: (String) -> HttpURLConnection = { URL(it).openConnection() as HttpURLConnection }
) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var busy = false
    private var candidate: JSONObject? = null
    private val apk get() = File(app.cacheDir, "updates/update.apk")
    private fun connection(url: String, binary: Boolean = false): HttpURLConnection {
        if (!UpdatePolicy.downloadHost(url)) throw UpdateFailure("invalid_response")
        return openConnection(url).apply {
            instanceFollowRedirects = false; connectTimeout = 10000; readTimeout = 20000; useCaches = false
            setRequestProperty("User-Agent", "FreeScene/${BuildConfig.VERSION_NAME} Android")
            setRequestProperty("Accept", if (binary) "application/octet-stream" else "application/vnd.github+json")
            setRequestProperty("X-GitHub-Api-Version", "2022-11-28")
        }
    }
    private fun json(url: String): String {
        val conn = connection(url)
        try {
            when (conn.responseCode) {
                200 -> {}
                401, 403, 404 -> throw UpdateFailure("github_access")
                else -> throw UpdateFailure("network")
            }
            val bytes = conn.inputStream.use { input ->
                val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                while (true) {
                    val n = input.read(buffer); if (n < 0) break
                    if (out.size() + n > 2 * 1024 * 1024) throw UpdateFailure("invalid_response")
                    out.write(buffer, 0, n)
                }
                out.toByteArray()
            }
            return bytes.toString(Charsets.UTF_8)
        } finally { conn.disconnect() }
    }
    private fun check(): Map<String, Any?> {
        candidate = null
        val releases = JSONArray(json("${UpdatePolicy.repository}/releases?per_page=20"))
        val abi = if (Build.SUPPORTED_ABIS.contains("arm64-v8a")) "arm64-v8a" else "armeabi-v7a"
        for (i in 0 until releases.length()) {
            val selected = UpdatePolicy.asset(releases.getJSONObject(i), BuildConfig.VERSION_NAME, BuildConfig.FLAVOR, abi) ?: continue
            if (candidate == null || UpdatePolicy.newer(selected.getString("version"), candidate!!.getString("version"))) candidate = selected
        }
        return mapOf("available" to (candidate != null), "version" to candidate?.optString("version"))
    }
    @Suppress("DEPRECATION")
    internal fun validate(file: File): Long {
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val incoming = app.packageManager.getPackageArchiveInfo(file.path, flags) ?: throw UpdateFailure("invalid_apk")
        val current = app.packageManager.getPackageInfo(app.packageName, flags)
        fun code(info: android.content.pm.PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        fun signatures(info: android.content.pm.PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        val old = signatures(current)?.map { it.toCharsString() }?.toSet()
        val next = signatures(incoming)?.map { it.toCharsString() }?.toSet()
        if (incoming.packageName != app.packageName || code(incoming) <= code(current) || old.isNullOrEmpty() || old != next)
            throw UpdateFailure("signature_or_version")
        if (incoming.applicationInfo?.minSdkVersion?.let { it > Build.VERSION.SDK_INT } == true) throw UpdateFailure("invalid_apk")
        return code(incoming)
    }
    private fun download(): Map<String, Any> {
        val asset = candidate ?: throw UpdateFailure("check_required")
        val expectedSize = asset.getLong("size")
        apk.parentFile!!.mkdirs(); apk.delete()
        val temp = File(apk.parentFile, "download.part"); temp.delete()
        var url = asset.getString("url")
        val deadline = System.nanoTime() + 180L * 1000000000L
        try {
            for (hop in 0..4) {
                val conn = connection(url, true)
                try {
                    if (conn.responseCode in listOf(301,302,303,307,308)) {
                        url = URL(URL(url), conn.getHeaderField("Location") ?: throw UpdateFailure("invalid_response")).toString()
                        if (!UpdatePolicy.downloadHost(url)) throw UpdateFailure("invalid_response")
                        continue
                    }
                    if (conn.responseCode != 200) throw UpdateFailure("network")
                    val digest = MessageDigest.getInstance("SHA-256"); var length = 0L
                    conn.inputStream.use { input -> temp.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            if (System.nanoTime() > deadline) throw UpdateFailure("network")
                            val n = input.read(buffer); if (n < 0) break
                            length += n
                            if (length > expectedSize || length > UpdatePolicy.maxApk) throw UpdateFailure("invalid_apk")
                            digest.update(buffer, 0, n); output.write(buffer, 0, n)
                        }
                        output.fd.sync()
                    } }
                    val hash = digest.digest().joinToString("") { "%02x".format(it) }
                    if (length != expectedSize || "sha256:$hash" != asset.getString("digest")) throw UpdateFailure("invalid_apk")
                    validate(temp)
                    if (!temp.renameTo(apk)) throw UpdateFailure("storage")
                    return mapOf("ready" to true)
                } finally { conn.disconnect() }
            }
            throw UpdateFailure("network")
        } finally { temp.delete() }
    }
    fun install(activity: Activity, result: MethodChannel.Result) {
        if (busy) { result.error("busy", "Update busy", null); return }
        try {
            if (!apk.isFile) throw UpdateFailure("check_required")
            val targetVersion = validate(apk)
            if (Build.VERSION.SDK_INT >= 26 && !app.packageManager.canRequestPackageInstalls()) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")))
                result.success(mapOf("permissionRequired" to true)); return
            }
            val uri = FileProvider.getUriForFile(app, "${app.packageName}.updates", apk)
            UpdateRestart.arm(app, targetVersion)
            activity.startActivity(UpdatePolicy.installerIntent(uri))
            result.success(mapOf("installing" to true))
        } catch (e: Exception) { UpdateRestart.cancel(app); result.error((e as? UpdateFailure)?.reason ?: "installer", "Could not start update", null) }
    }
    fun request(method: String, result: MethodChannel.Result) {
        if (busy) { result.error("busy", "Update busy", null); return }
        busy = true
        worker.execute {
            try {
                val response: Any = when (method) {
                    "updateCheck" -> check()
                    "updateDownload" -> download()
                    else -> throw UpdateFailure("unsupported")
                }
                main.post { busy = false; result.success(response) }
            } catch (e: Exception) {
                main.post { busy = false; result.error((e as? UpdateFailure)?.reason ?: "network", "Update unavailable", null) }
            }
        }
    }
}
