package com.opencapture.openinstacine.monitor.media

import android.content.Context
import android.content.SharedPreferences
import com.opencapture.openinstacine.monitor.OperatorPrefs
import java.io.File
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaCacheGrade

class MediaCache(
    private val filesDir: File,
    private val prefs: SharedPreferences,
    private val storage: com.opencapture.opencine.appkit.MonitorMediaCacheStorage,
) {
    fun cacheRoot(cameraId: String): File =
        File(filesDir, "OpenPocketCine/media/$cameraId")

    fun thumbnailFile(cameraId: String, file: MediaFile): File =
        File(File(cacheRoot(cameraId), "thumbs"), cacheName(file.thumbPath) + ".jpg")

    fun fileCache(cameraId: String, file: MediaFile): File =
        File(File(cacheRoot(cameraId), "files"), cacheName(file.path))

    fun playbackCache(cameraId: String, file: MediaFile, path: String): File {
        if (path == file.path) return fileCache(cameraId, file)
        return File(File(cacheRoot(cameraId), "play"), MediaHTTP.playbackCacheFileName(path))
    }

    fun catalogFile(cameraId: String): File = File(cacheRoot(cameraId), "index.json")

    fun existingFile(file: File): File? {
        if (!file.isFile || file.length() <= 0L) return null
        return file
    }

    fun isDownloaded(file: MediaFile, cameraId: String): Boolean {
        val onDisk = existingFile(fileCache(cameraId, file)) ?: return false
        return isCompleteDownload(onDisk.length(), file.sizeBytes)
    }

    fun localPlaybackFile(file: MediaFile, cameraId: String): File? {
        localProxyFile(file, cameraId)?.let { return it }
        if (isDownloaded(file, cameraId)) return fileCache(cameraId, file)
        return null
    }

    /** 720p LRF/XRF sidecar, never the 4K original. */
    fun localProxyFile(file: MediaFile, cameraId: String): File? {
        for (path in MediaHTTP.proxyPaths(file)) {
            existingFile(playbackCache(cameraId, file, path))?.let { return it }
        }
        return null
    }

    fun isAvailableOffline(file: MediaFile, cameraId: String): Boolean =
        localPlaybackFile(file, cameraId) != null

    fun cacheGrade(file: MediaFile, cameraId: String): MediaCacheGrade =
        MediaCacheGrade.resolve(
            hasOriginal = isDownloaded(file, cameraId),
            hasProxy = localProxyFile(file, cameraId) != null,
        )

    /** The library's own directory (one per canonical root), so its clears fence the shot colors. */
    private fun shotColors(cameraId: String) = storage.directory(cacheRoot(cameraId)).shotColors

    fun shotColor(path: String, cameraId: String, context: Context? = null): Int {
        migrateLegacyShotColors(cameraId, context)
        return shotColors(cameraId).color(path) ?: -1
    }

    fun rememberShotColor(path: String, colorMode: Int, cameraId: String) {
        shotColors(cameraId).remember(path, colorMode)
    }

    private fun migrateLegacyShotColors(cameraId: String, context: Context?) {
        val ctx = context ?: return
        val raw = OperatorPrefs.legacyClipShotColorJson(ctx) ?: return
        shotColors(cameraId).adopt(raw.keys().asSequence().associateWith { raw.optInt(it, -1) })
        OperatorPrefs.clearLegacyClipShotColor(ctx)
    }

    companion object {
        private const val LAST_CAMERA_KEY = "opc.media.lastCameraID"

        fun favoritesKey(cameraId: String): String = "opc.media.fav.$cameraId"

        fun cacheName(path: String): String = path.replace("/", "_")

        /** Complete only at the expected length (OpenZCine cache contract). */
        fun isCompleteDownload(onDisk: Long, sizeBytes: Long): Boolean {
            if (onDisk <= 0L) return false
            if (sizeBytes <= 0L) return true
            return onDisk == sizeBytes
        }
    }
}
