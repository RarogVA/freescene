package local.freescene.freescene

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.source.BundledExtractorsAdapter
import androidx.media3.exoplayer.source.ProgressiveMediaExtractor
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory

/** Keep Media3 1.11.1 retries at the requested torrent range if open() fails.
 * ProgressiveMediaPeriod reads the extractor position in finally even when
 * open() failed before init(). The old input must not supply that position.
 */
internal object TorrentMediaSource {
    fun factory(
        upstream: DataSource.Factory,
        extractors: ExtractorsFactory = DefaultExtractorsFactory(),
    ) = ProgressiveMediaSource.Factory(
        DataSource.Factory { OpenedDataSource(upstream.createDataSource()) },
        ProgressiveMediaExtractor.Factory {
            OpenedInputExtractor(BundledExtractorsAdapter(extractors))
        },
    )

    // DataSource.getUri() is null while closed, including a partially failed
    // open. StatsDataSource forwards this contract to the extractor's reader.
    internal class OpenedDataSource(private val upstream: DataSource) : DataSource by upstream {
        private var opened = false
        override fun open(dataSpec: DataSpec): Long {
            opened = false
            val length = upstream.open(dataSpec)
            opened = true
            return length
        }
        override fun getUri(): Uri? = if (opened) upstream.uri else null
        override fun close() {
            opened = false
            upstream.close()
        }
    }

    internal class OpenedInputExtractor(private val delegate: ProgressiveMediaExtractor) : ProgressiveMediaExtractor by delegate {
        private var input: DataSource? = null
        override fun init(dataReader: DataReader, uri: Uri, responseHeaders: Map<String, List<String>>,
                          position: Long, length: Long, output: ExtractorOutput) {
            input = dataReader as? DataSource
            delegate.init(dataReader, uri, responseHeaders, position, length, output)
        }
        override fun getCurrentInputPosition(): Long =
            if (input?.uri == null) C.INDEX_UNSET.toLong() else delegate.currentInputPosition
        override fun release() {
            input = null
            delegate.release()
        }
    }
}
