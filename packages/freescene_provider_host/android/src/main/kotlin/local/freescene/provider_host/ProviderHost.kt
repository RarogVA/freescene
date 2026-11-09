package local.freescene.provider_host
import android.content.Context
/** Native adapters own website rules and cookies. The player owns UI and history. */
interface WebProvider {
    fun player(provider: String?, url: String?): Boolean
    fun sameTitle(provider: String, target: String?, source: String): Boolean
    fun navigation(provider: String, target: String?, source: String, mainFrame: Boolean): Boolean
    fun blockedRequest(provider: String, url: String): Boolean = false
    fun prepare(context: Context, provider: String, done: (Boolean) -> Unit) = done(true)
    fun script(provider: String, index: Int): String? = null
    fun rootSelector(provider: String): String? = null
    fun historyKey(provider: String, source: String): String? = null
    fun referrer(media: String?, page: String?): String? = null
}
object ProviderHost {
    @Volatile var web: WebProvider? = null
}
