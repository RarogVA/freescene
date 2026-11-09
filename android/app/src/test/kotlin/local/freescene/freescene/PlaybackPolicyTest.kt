package local.freescene.freescene

import org.junit.Assert.*
import org.junit.Test

class PlaybackPolicyTest {
    @Test fun rejectsUnsafeMediaAtBoundary() {
        for (url in listOf(null, "", "http://video.test/a", "file:///etc/passwd", "content://app/x",
                "javascript:alert(1)", "https://user:password@video.test/x", "https://video.test:8080/x", "https:///x")) {
            assertFalse(url, PlaybackPolicy.allowed(url))
        }
        assertTrue(PlaybackPolicy.allowed("https://cdn.test/video.m3u8?token=fixture"))
    }
    @Test fun lowMemoryBudgetAndSeekingAreBounded() {
        assertEquals(24 * 1024 * 1024, PlaybackPolicy.bufferBytes(true))
        assertTrue(PlaybackPolicy.bufferBytes(true) < PlaybackPolicy.bufferBytes(false))
        assertEquals(0L, PlaybackPolicy.seek(2000, -10000, 30000))
        assertEquals(30000L, PlaybackPolicy.seek(25000, 10000, 30000))
        assertEquals(35000L, PlaybackPolicy.seek(25000, 10000, -1))
    }
}
