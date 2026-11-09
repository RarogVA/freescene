package local.freescene.freescene
import java.net.URI
import local.freescene.provider_host.ProviderHost
/** Generic channel boundary. Unregistered providers cannot open a web player. */
object WebPolicy {
    fun https(value: String?): URI? = try {
        URI(value ?: "").takeIf { value != null && value.length <= 8192 && it.scheme == "https" &&
            !it.host.isNullOrEmpty() && it.rawUserInfo == null && (it.port == -1 || it.port == 443) }
    } catch (_: Exception) { null }
    fun player(provider: String?, value: String?) = https(value) != null && ProviderHost.web?.player(provider, value) == true
    fun sameTitle(provider: String, target: String?, source: String) = https(target) != null && ProviderHost.web?.sameTitle(provider, target, source) == true
    fun navigation(provider: String, target: String?, source: String, mainFrame: Boolean) =
        ProviderHost.web?.navigation(provider, target, source, mainFrame) == true
}
