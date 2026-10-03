package com.opencapture.openpocketcine.media

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.util.Locale

data class MediaFile(
    val path: String,
    val thumbPath: String,
    val handle: Long = 0,
    val cmdHandle: Long = 0,
    val sizeBytes: Long = 0,
    val durationSeconds: Int = 0,
    val isStarred: Boolean = false,
    val resolution: String? = null,
    val fps: Int? = null,
    val proxyPath: String? = null,
    val storage: Int = 0,
    /** True when storage came from the counter of a store-specific `0x26` query. */
    val storageKnown: Boolean = false,
    val group: Int = 0,
    val handleShared: Boolean = false,
    /**
     * The handle read at the marker fixed position, before the base+step fit has vouched for it.
     * Retained legacy index field. Zero when the original record had no marker.
     */
    val handleCandidate: Long = 0L,
) {
    val id: String get() = MediaListCommand.pageKey(this)
    val filename: String get() = path.substringAfterLast('/')
    val fileExtension: String get() = filename.substringAfterLast('.', missingDelimiterValue = "").uppercase(Locale.US)
    val kind: MediaKind get() = MediaKind.fromExtension(fileExtension)
    val isDeletable: Boolean get() = handle != 0L && !handleShared
    val favoriteHandle: Long get() = if (handle != 0L) handle else cmdHandle

    /** `YYYYMMDDHHmmss` baked into `DJI_20260814125250_0034_D.MP4`. */
    val filenameTimestamp: String?
        get() = TIMESTAMP_REGEX.find(filename)?.groupValues?.getOrNull(1)
            // Insta360 `VID_20260916_123456_00_001.mp4` / `IMG_...`.
            ?: INSTA360_REGEX.find(filename)?.groupValues?.let { it[1] + it[2] }

    val dateKey: String
        get() = filenameTimestamp?.take(8).orEmpty()

    /** `DJI_…_0034_D` sequence used to fit `base + seq × step`. */
    val sequenceNumber: Int
        get() = SEQUENCE_REGEX.find(filename)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 0

    val burstGroupKey: String?
        get() = BURST_REGEX.find(filename)?.groupValues?.getOrNull(1)

    val burstIndex: Int
        get() = BURST_REGEX.find(filename)?.groupValues?.getOrNull(2)?.toIntOrNull() ?: 0

    val isBurstLead: Boolean get() = burstGroupKey != null

    companion object {
        private val TIMESTAMP_REGEX = Regex("_(\\d{14})_")
        private val INSTA360_REGEX = Regex("_(\\d{8})_(\\d{6})_")
        private val SEQUENCE_REGEX = Regex("_(\\d{4})_D")
        private val BURST_REGEX = Regex("""^(.+)_(\d{3})\.\w+$""")
    }
}

enum class MediaKind {
    VIDEO,
    PHOTO,
    ;

    companion object {
        fun fromExtension(ext: String): MediaKind =
            when (ext.uppercase(Locale.US)) {
                "JPG", "JPEG", "DNG", "HEIC", "TIF", "TIFF", "PANO" -> PHOTO
                else -> VIDEO
            }
    }
}

/** iOS `MediaCacheGrade`. Playback grades the proxy; Share needs the original. */
enum class MediaCacheGrade {
    NONE,
    PROXY,
    ORIGINAL,
    ;

    val isPlayableOffline: Boolean get() = this != NONE
    val isProxyOnly: Boolean get() = this == PROXY

    companion object {
        fun resolve(hasOriginal: Boolean, hasProxy: Boolean): MediaCacheGrade =
            when {
                hasOriginal -> ORIGINAL
                hasProxy -> PROXY
                else -> NONE
            }
    }
}

/**
 * Where one camera serves its files: DJI serves `/v2?storage=&path=` on [MediaHTTP.HOST]; Insta360
 * serves each file at its own path. Per session ([com.opencapture.openpocketcine.session.CameraProfile]).
 */
data class MediaRoute(val host: String = MediaHTTP.HOST, val directPath: Boolean = false) {
    fun pathUrlString(storage: Int, path: String): String =
        if (directPath) "http://$host${if (path.startsWith("/")) path else "/$path"}"
        else "http://$host/v2?storage=$storage&path=$path"

    fun pathUrl(storage: Int, path: String): HttpUrl = pathUrlString(storage, path).toHttpUrl()

    companion object {
        val DJI = MediaRoute()
    }
}

/** SoftAP HTTP `/v2` paths. Osmosis `PathAddressing` + `StorageRules`. */
object MediaHTTP {
    const val HOST = "192.168.2.1"
    const val PORT = 80

    /**
     * Guess `/v2?storage=` from the delete handle's `0x40000000` bit.
     * Internal → 1, SD → 0. Pocket 3 is the single-microSD exception (`0`).
     */
    fun storageGuess(handle: Long, singleSdStorage: Boolean): Int {
        if (singleSdStorage) return 0
        return if ((handle and MediaListCommand.INTERNAL_BIT) != 0L) 1 else 0
    }

    /**
     * `/v2?storage=` for a listed clip. Pocket 3 (single microSD) is always 0,
     * even when the manifest stamped storage 1 from the internal-handle bit or a
     * previous GET remembered 1.
     */
    fun resolvedStorage(
        stamped: Int,
        handle: Long,
        winner: Int?,
        singleSdStorage: Boolean,
    ): Int {
        if (singleSdStorage) return 0
        winner?.let { if (it == 0 || it == 1) return it }
        if (stamped == 0 || stamped == 1) return stamped
        return storageGuess(handle, singleSdStorage = false)
    }

    fun originalPath(file: MediaFile): String = file.path

    /** Clip delivery / export: the original camera file, never the LRF/XRF 720p proxy. */
    fun deliveryPath(file: MediaFile): String = originalPath(file)

    fun thumbnailPath(file: MediaFile): String = file.thumbPath

    /** Preview chain: listed proxy, derived `.LRF` (DJI) / `.XRF` (CAM_), then original. */
    fun previewPaths(file: MediaFile): List<String> {
        val seen = LinkedHashSet<String>()
        file.proxyPath?.let { seen.add(it) }
        derivedProxyPath(file)?.let { seen.add(it) }
        seen.add(file.path)
        return seen.toList()
    }

    /** LRF/XRF sidecars only. Empty for photos and clips with no DJI proxy. */
    fun proxyPaths(file: MediaFile): List<String> = previewPaths(file).filter(::isProxyPath)

    fun derivedProxyPath(file: MediaFile): String? {
        val ext = derivedProxyExtension(file.filename) ?: return null
        return "${deletingPathExtension(file.path)}.$ext"
    }

    fun derivedProxyExtension(filename: String): String? =
        when {
            filename.startsWith("CAM_") -> "XRF"
            filename.startsWith("DJI_") -> "LRF"
            else -> null
        }

    fun isProxyPath(path: String): Boolean =
        when (pathExtension(path).uppercase(Locale.US)) {
            "LRF", "LRV", "XRF" -> true
            else -> false
        }

    fun playbackMIMEType(path: String): String =
        when (pathExtension(path).uppercase(Locale.US)) {
            "JPG", "JPEG" -> "image/jpeg"
            "DNG" -> "image/x-adobe-dng"
            "HEIC" -> "image/heic"
            else -> "video/mp4"
        }

    fun playbackCacheFileName(path: String): String {
        val raw = path.replace("/", "_")
        return when (pathExtension(raw).uppercase(Locale.US)) {
            "MP4", "MOV" -> raw
            else -> "${deletingPathExtension(raw)}.mp4"
        }
    }
}

/** Legacy storage qualification retained for saved index and native playback addresses. */
object MediaListCommand {
    const val INTERNAL_BIT = 0x40000000L
    fun storeOf(file: MediaFile): Int {
        if (file.storageKnown) return file.storage
        val handle = if (file.handle != 0L) file.handle else file.cmdHandle
        if (handle != 0L) return if ((handle and INTERNAL_BIT) == 0L) 0 else 1
        return if (file.group == 1) 1 else 0
    }
    fun pageKey(file: MediaFile): String = "${storeOf(file)}:${file.path}"
}

enum class MediaLibraryTab {
    ALL,
    VIDEOS,
    PHOTOS,
    FAVORITES,
}

enum class MediaLibrarySort {
    NEWEST,
    OLDEST,
    NAME,
    RATING,
    ;

    val next: MediaLibrarySort
        get() =
            when (this) {
                NEWEST -> OLDEST
                OLDEST -> NAME
                NAME -> RATING
                RATING -> NEWEST
            }

    val menuLabel: String
        get() =
            when (this) {
                NEWEST -> "Newest"
                OLDEST -> "Oldest"
                NAME -> "Name"
                RATING -> "Rating"
            }
}

enum class MediaBrowserLayout {
    GRID,
    LIST,
}

enum class MediaThumbnailSize {
    SMALL,
    MEDIUM,
    LARGE,
    ;

    val gridMinimumDp: Int
        get() =
            when (this) {
                SMALL -> 148
                MEDIUM -> 210
                LARGE -> 280
            }

    val gridMaximumDp: Int
        get() =
            when (this) {
                SMALL -> 200
                MEDIUM -> 300
                LARGE -> 380
            }

    val gridIconSizeDp: Int
        get() =
            when (this) {
                SMALL -> 9
                MEDIUM -> 12
                LARGE -> 15
            }

    val accessibilityLabel: String
        get() =
            when (this) {
                SMALL -> "Small thumbnails"
                MEDIUM -> "Medium thumbnails"
                LARGE -> "Large thumbnails"
            }
}

object MediaLibraryQuery {
    /** Filename `YYYYMMDD` as UTC calendar year-month-day. Not an instant. */
    fun dateKeyFromMillis(millis: Long): String {
        val date = java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
        return String.format(Locale.US, "%04d%02d%02d", date.year, date.monthValue, date.dayOfMonth)
    }

    fun millisFromDateKey(key: String): Long? {
        if (key.length != 8) return null
        val year = key.substring(0, 4).toIntOrNull() ?: return null
        val month = key.substring(4, 6).toIntOrNull() ?: return null
        val day = key.substring(6, 8).toIntOrNull() ?: return null
        return runCatching {
            java.time.LocalDate.of(year, month, day)
                .atStartOfDay(java.time.ZoneOffset.UTC)
                .toInstant()
                .toEpochMilli()
        }.getOrNull()
    }

}

object MediaClipFormatting {
    fun durationLabel(seconds: Int): String {
        if (seconds <= 0) return "0:00"
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) {
            String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        } else {
            String.format(Locale.US, "%d:%02d", m, s)
        }
    }

    fun durationLabel(seconds: Double): String {
        if (!seconds.isFinite() || seconds < 0) return "0:00"
        return durationLabel(seconds.toInt())
    }

    fun byteLabel(bytes: Long): String {
        if (bytes <= 0L) return ""
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format(Locale.US, "%.0f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format(Locale.US, "%.1f MB", mb)
        return String.format(Locale.US, "%.2f GB", mb / 1024.0)
    }
}

object MediaClipPresentation {
    fun resolutionLabel(resolution: String?): String? {
        if (resolution.isNullOrEmpty()) return null
        val width = resolution.substringBefore('x').toIntOrNull()
        return when {
            width == null -> resolution
            width >= 3840 -> "4K"
            width >= 2560 -> "2.7K"
            width >= 1920 -> "1080p"
            width >= 1280 -> "720p"
            else -> resolution
        }
    }

    fun dateLabel(dateKey: String): String {
        if (dateKey.length != 8) return dateKey
        return "${dateKey.substring(0, 4)}-${dateKey.substring(4, 6)}-${dateKey.substring(6, 8)}"
    }

    fun metadataLine(file: MediaFile, durationOverride: String? = null): String {
        val parts = ArrayList<String>(3)
        resolutionLabel(file.resolution)?.let { parts.add(it) }
        val bytes = MediaClipFormatting.byteLabel(file.sizeBytes)
        if (bytes.isNotEmpty()) parts.add(bytes)
        if (file.kind == MediaKind.VIDEO) {
            parts.add(durationOverride ?: MediaClipFormatting.durationLabel(file.durationSeconds))
        }
        return parts.joinToString(" · ")
    }
}

/** Operator-facing media-browser copy. Never name a sister app. */
object MediaLibraryCopy {
    const val FILTER_EMPTY = "Nothing in this tab matches the filters."
    const val EMPTY_ALL = "Nothing on this camera yet. Record a clip, then pull to refresh."
    const val EMPTY_FAVORITES = "Nothing favorited yet. Star a clip to find it here."
    const val EMPTY_VIDEOS = "No videos on this camera yet. Record a clip, then pull to refresh."
    const val EMPTY_PHOTOS = "No photos on this camera yet. Capture a still, then pull to refresh."
    const val DISCONNECTED = "Connect the camera to list clips on the body."
    const val DISCONNECTED_EMPTY_CACHE =
        "Nothing cached on this phone. Connect the camera to list clips on the body."
    const val PROXY_TAG = "Proxy"
    const val PROXY_HELP = "720p preview. Connect the camera to share the original."
}

object MediaOperatorCopy {
    const val LISTING = "Listing camera clips…"
    const val NOT_CONNECTED = "Connect the camera to list clips."
    const val PLAYBACK_FAILED = "Camera did not enter playback."
    const val BROWSING_ON_CAMERA = "Playback is open on the camera. Close to return to live view."
    const val NO_CLIPS = "No clips on the camera."
    const val LIST_FAILED = "Could not list camera clips."
    const val NOT_DELETABLE = "That clip cannot be deleted from here."
    const val DELETE_FAILED = "Could not delete that clip."
    const val DOWNLOAD_FAILED = "Could not download that clip."
    const val THUMB_FAILED = "Could not load that thumbnail."
    const val CLIP_OPEN_FAILED = "Could not open that clip."
    const val CLIP_LOADING = "Loading clip from camera…"
    const val CLIP_NOT_CACHED = "This clip is not cached on the phone."
}

internal fun pathExtension(path: String): String {
    val name = path.substringAfterLast('/')
    val dot = name.lastIndexOf('.')
    if (dot < 0) return ""
    return name.substring(dot + 1)
}

internal fun deletingPathExtension(path: String): String {
    val slash = path.lastIndexOf('/')
    val dot = path.lastIndexOf('.')
    if (dot <= slash) return path
    return path.substring(0, dot)
}
