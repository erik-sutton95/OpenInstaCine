package com.opencapture.openinstacine.monitor.media

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import com.opencapture.opencine.vocabulary.MediaRoute
import com.opencapture.opencine.vocabulary.MediaLibraryQuery
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaCacheGrade
import com.opencapture.opencine.cameracontrols.MediaOperatorCopy
import com.opencapture.opencine.cameracontrols.MediaLibraryCopy
import com.opencapture.opencine.cameracontrols.MediaClipPresentation

class MediaLibraryTest {
    @Test
    fun nativeDatePickerAndResolutionLabelsStayCompatible() {
        val key = "20260814"
        assertEquals(key, MediaLibraryQuery.dateKeyFromMillis(MediaLibraryQuery.millisFromDateKey(key)!!))
        assertEquals("4K", MediaClipPresentation.resolutionLabel("3840x2160"))
        assertEquals("1080p", MediaClipPresentation.resolutionLabel("1920x1080"))
    }

    @Test
    fun emptyCopyDoesNotNameSisterApps() {
        val copy =
            listOf(
                MediaLibraryCopy.FILTER_EMPTY,
                MediaLibraryCopy.EMPTY_ALL,
                MediaLibraryCopy.EMPTY_FAVORITES,
                MediaLibraryCopy.EMPTY_VIDEOS,
                MediaLibraryCopy.EMPTY_PHOTOS,
                MediaLibraryCopy.DISCONNECTED,
                MediaLibraryCopy.DISCONNECTED_EMPTY_CACHE,
                MediaOperatorCopy.CLIP_NOT_CACHED,
            )
        for (text in copy) {
            assertFalse(text.contains("OpenZCine", ignoreCase = true))
            assertFalse(text.contains("Nikon", ignoreCase = true))
            assertFalse(text.contains("protocol is not", ignoreCase = true))
        }
    }

    @Test
    fun httpPathsUseStorageAndScr() {
        val file = MediaFile(
            path = "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath = "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            handle = 0x40100880L,
        )
        val storage = MediaHTTP.storageGuess(file.handle, singleSdStorage = false)
        assertEquals(1, storage)
        assertEquals(
            0,
            MediaHTTP.resolvedStorage(
                stamped = 1,
                handle = file.handle,
                winner = 1,
                singleSdStorage = true,
            ),
        )
        assertEquals(
            1,
            MediaHTTP.resolvedStorage(
                stamped = 1,
                handle = file.handle,
                winner = null,
                singleSdStorage = false,
            ),
        )
        val thumb = MediaRoute.CAMERA_SOFT_AP.pathUrlString(storage, file.thumbPath)
        assertEquals(
            "http://192.168.2.1/v2?storage=1&path=MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            thumb,
        )
        val original = MediaRoute.CAMERA_SOFT_AP.pathUrlString(storage, file.path)
        assertTrue(original.contains("DCIM/DJI_001/DJI_20260814125250_0034_D.MP4"))
        assertTrue(MediaHTTP.previewPaths(file).any { it.endsWith(".LRF") })
        val proxy = MediaHTTP.previewPaths(file).first()
        assertTrue(MediaHTTP.isProxyPath(proxy))
        assertFalse(MediaHTTP.isProxyPath(file.path))
        assertEquals(file.path, MediaHTTP.deliveryPath(file))
        assertFalse(MediaHTTP.isProxyPath(MediaHTTP.deliveryPath(file)))
        assertTrue(MediaHTTP.previewPaths(file).first() != MediaHTTP.deliveryPath(file))
        assertTrue(MediaHTTP.proxyPaths(file).all { MediaHTTP.isProxyPath(it) })
        assertTrue(MediaHTTP.proxyPaths(file).none { it == file.path })
        assertTrue(MediaHTTP.proxyPaths(file).isNotEmpty())
        assertEquals("video/mp4", MediaHTTP.playbackMIMEType(proxy))
        assertEquals("video/mp4", MediaHTTP.playbackMIMEType(file.path))
        assertTrue(MediaHTTP.playbackCacheFileName(proxy).endsWith(".mp4"))
        assertTrue(MediaHTTP.playbackCacheFileName(file.path).endsWith(".MP4"))
        assertEquals(MediaCacheGrade.ORIGINAL, MediaCacheGrade.resolve(true, true))
        assertEquals(MediaCacheGrade.PROXY, MediaCacheGrade.resolve(false, true))
        assertEquals(MediaCacheGrade.NONE, MediaCacheGrade.resolve(false, false))
        assertTrue(MediaCacheGrade.PROXY.isProxyOnly)
        assertTrue(MediaRoute.CAMERA_SOFT_AP.pathUrl(storage, file.thumbPath).encodedPath == "/v2")
    }

    @Test
    fun downloadFinishesAtContentLengthWithoutWaitingForEof() {
        val body = ByteArray(100) { it.toByte() }
        val padded = body + ByteArray(40) { 0xFF.toByte() }
        val out = ByteArrayOutputStream()
        val written = MediaTransfer.readUntilLength(ByteArrayInputStream(padded), out, expected = 100) { }
        assertEquals(100L, written)
        assertEquals(100, out.size())
        assertEquals(body.toList(), out.toByteArray().toList())
    }

    @Test
    fun ramCopyEnforcesMaxBytesForKnownAndUnknownLengths() {
        data class Case(val name: String, val size: Int, val expected: Long, val rejects: Boolean)
        val cases =
            listOf(
                Case("unknown length past max is rejected", size = 200, expected = 0, rejects = true),
                Case("unknown length within max succeeds", size = 50, expected = 0, rejects = false),
                Case("unknown length at exact max succeeds", size = 100, expected = 0, rejects = false),
                Case("known length above max is rejected without copying", size = 200, expected = 200, rejects = true),
            )
        for (case in cases) {
            val body = ByteArray(case.size) { it.toByte() }
            val out = ByteArrayOutputStream()
            val read = {
                MediaTransfer.readUntilLength(
                    ByteArrayInputStream(body),
                    out,
                    expected = case.expected,
                    maxBytes = 100,
                ) { }
            }
            if (case.rejects) {
                assertFailsWith<MediaTransferError.BadResponse>(case.name) { read() }
                if (case.expected == 0L) {
                    assertTrue(out.size() <= 100, case.name)
                } else {
                    assertEquals(0, out.size(), case.name)
                }
            } else {
                assertEquals(case.size.toLong(), read(), case.name)
                assertEquals(body.toList(), out.toByteArray().toList(), case.name)
            }
        }
    }

    @Test
    fun downloadIsCompleteOnlyAtExactExpectedLength() {
        assertTrue(MediaCache.isCompleteDownload(100, 100))
        assertFalse(MediaCache.isCompleteDownload(90, 100))
        assertTrue(MediaCache.isCompleteDownload(1, 0))
        assertFalse(MediaCache.isCompleteDownload(0, 100))
    }
}
