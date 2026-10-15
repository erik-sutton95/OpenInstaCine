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
    fun downloadIsCompleteOnlyAtExactExpectedLength() {
        assertTrue(MediaCache.isCompleteDownload(100, 100))
        assertFalse(MediaCache.isCompleteDownload(90, 100))
        assertTrue(MediaCache.isCompleteDownload(1, 0))
        assertFalse(MediaCache.isCompleteDownload(0, 100))
    }
}
