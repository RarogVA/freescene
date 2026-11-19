package local.freescene.freescene

import android.content.Context
import java.io.File
import java.security.KeyStore

/** OpenSSL keeps this path process-wide, beyond disposable probe/TV sessions. */
internal object TorrentCertificates {
    @Synchronized fun bundle(context: Context): File {
        val store = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
        val pem = store.aliases().toList().mapNotNull { store.getCertificate(it) }.joinToString("\n") {
            "-----BEGIN CERTIFICATE-----\n" + android.util.Base64.encodeToString(it.encoded, android.util.Base64.NO_WRAP)
                .chunked(64).joinToString("\n") + "\n-----END CERTIFICATE-----"
        }
        return publish(context.filesDir, pem)
    }

    @Synchronized internal fun publish(files: File, pem: String): File {
        val ca = File(files, "torrent-ca.pem")
        check(pem.isNotEmpty()) { "Android certificate store is empty" }
        val temporary = File(files, "torrent-ca.pem.tmp")
        temporary.writeText(pem)
        check(temporary.renameTo(ca)) { "Could not install torrent certificates" }
        return ca
    }
}
