package local.freescene.freescene

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SourceProbeTest {
    @Test fun malformedSourceIsRejectedBeforeStartingNativeWorkEvenWithAnotherValidField() {
        val magnet = "magnet:?xt=urn:btih:" + "a".repeat(40)
        for (args in listOf(
            emptyMap(),
            mapOf("bytes" to byteArrayOf(), "magnet" to magnet),
            mapOf("bytes" to "not a torrent".toByteArray(), "magnet" to magnet),
            mapOf("bytes" to ByteArray(16 * 1024 * 1024 + 1), "magnet" to magnet),
            mapOf("bytes" to "de".toByteArray(), "magnet" to "https://invalid.example/"),
        )) {
            var answer: Any? = null
            SourceProbe.start(RuntimeEnvironment.getApplication(), MethodCall("sourceProbe", args), object : MethodChannel.Result {
                override fun success(result: Any?) { answer = result }
                override fun error(code: String, message: String?, details: Any?) { fail(code) }
                override fun notImplemented() { fail("not implemented") }
            })
            assertEquals("unavailable", answer)
        }
    }
}
