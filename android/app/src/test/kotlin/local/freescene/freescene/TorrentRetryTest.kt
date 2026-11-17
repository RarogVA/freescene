package local.freescene.freescene

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.util.ConditionVariable
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.BundledExtractorsAdapter
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaExtractor
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.upstream.DefaultAllocator
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.lang.reflect.InvocationTargetException
import java.net.SocketTimeoutException

/** Exercise the real Media3 load/finally/retry path, not a copy of its logic. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TorrentRetryTest {
    private class Bytes : DataSource {
        val opens = mutableListOf<Long>()
        var failOpen = false
        var failRead = false
        private var position = 0L
        private var bytesRead = 0
        override fun addTransferListener(listener: TransferListener) {}
        override fun getUri(): Uri = Uri.parse("http://127.0.0.1:8080/video")
        override fun open(spec: DataSpec): Long {
            opens.add(spec.position)
            if (failOpen) throw SocketTimeoutException("No first piece")
            position = spec.position
            bytesRead = 0
            return 10_000_000 - position
        }
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (failRead && bytesRead > 0) throw SocketTimeoutException("Next piece stalled")
            buffer[offset] = 0
            bytesRead++
            position++
            return 1
        }
        override fun close() {}
    }
    private class Reader : Extractor {
        var readTwice = false
        override fun sniff(input: ExtractorInput) = true
        override fun init(output: ExtractorOutput) {}
        override fun seek(position: Long, timeUs: Long) {}
        override fun release() {}
        override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
            input.readFully(ByteArray(1), 0, 1)
            if (readTwice) input.readFully(ByteArray(1), 0, 1)
            return Extractor.RESULT_END_OF_INPUT
        }
    }
    private fun exercise(block: (Bytes, Reader, Any, (Long) -> Unit, () -> Unit) -> Unit) {
        val bytes = Bytes()
        val reader = Reader()
        val dataSource = TorrentMediaSource.OpenedDataSource(bytes)
        val extractor: ProgressiveMediaExtractor = TorrentMediaSource.OpenedInputExtractor(
            BundledExtractorsAdapter(ExtractorsFactory { arrayOf(reader) }))
        val source = ProgressiveMediaSource.Factory(DataSource.Factory { dataSource },
            ProgressiveMediaExtractor.Factory { extractor }).createMediaSource(MediaItem.fromUri(bytes.uri))
        val caller = MediaSource.MediaSourceCaller { _, _ -> }
        source.prepareSource(caller, PlayerId.UNSET, androidx.media3.exoplayer.upstream.DefaultBandwidthMeter.Builder(org.robolectric.RuntimeEnvironment.getApplication()).build())
        val period = source.createPeriod(MediaSource.MediaPeriodId(Any()), DefaultAllocator(true, 65536), 0)
        // ExtractingLoadable is package-private. Reflection keeps the test on
        // the pinned library's actual implementation without vendoring it.
        val type = Class.forName("androidx.media3.exoplayer.source.ProgressiveMediaPeriod\$ExtractingLoadable")
        val constructor = type.declaredConstructors.single().apply { isAccessible = true }
        val loadable = constructor.newInstance(period, bytes.uri, dataSource, extractor,
            period as ExtractorOutput, ConditionVariable().apply { open() })
        val setPosition = type.getDeclaredMethod("setLoadPosition", Long::class.javaPrimitiveType, Long::class.javaPrimitiveType).apply { isAccessible = true }
        val load = type.getDeclaredMethod("load").apply { isAccessible = true }
        try {
            block(bytes, reader, loadable, { at -> setPosition.invoke(loadable, at, 0L) }, {
                try { load.invoke(loadable) }
                catch (failure: InvocationTargetException) { throw failure.cause!! }
            })
        } finally {
            source.releasePeriod(period)
            source.releaseSource(caller)
        }
    }
    private fun expectTimeout(load: () -> Unit) {
        try { load(); fail("Expected timeout") } catch (_: SocketTimeoutException) {}
    }

    @Test fun failedForwardAndBackwardOpensRetryTheRequestedRange() = exercise { bytes, _, _, seek, load ->
        seek(30_000); load()
        for (target in listOf(176_000L, 12_000L)) {
            seek(target)
            bytes.failOpen = true
            repeat(2) { expectTimeout(load) }
            bytes.failOpen = false
            load()
            assertEquals(listOf(target, target, target), bytes.opens.takeLast(3))
        }
    }

    @Test fun aNewSeekAfterFailedOpenSupersedesTheFailedTarget() = exercise { bytes, _, _, seek, load ->
        seek(30_000); load()
        seek(176_000); bytes.failOpen = true; expectTimeout(load)
        seek(500_000); expectTimeout(load)
        bytes.failOpen = false; load()
        assertEquals(listOf(30_000L, 176_000L, 500_000L, 500_000L), bytes.opens)
    }

    @Test fun readFailureResumesAfterConsumedBytesInsteadOfReplayingTheRange() = exercise { bytes, reader, _, seek, load ->
        seek(176_000)
        reader.readTwice = true; bytes.failRead = true; expectTimeout(load)
        bytes.failRead = false; load()
        assertEquals(listOf(176_000L, 176_001L), bytes.opens)
    }
}
