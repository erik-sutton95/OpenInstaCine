package com.opencapture.openpocketcine.media

import android.content.Context
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.*
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openpocketcine.lut.ClipColorProfile
import com.opencapture.openpocketcine.feed.fromColorMode
import com.opencapture.openpocketcine.session.PocketCameraSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/** Source look/OS playback adapters only; the gallery consumes the common library directly. */
data class LunaPlaybackLook(val colorMode: Int?, val file: MediaFile)

class LunaMediaPlaybackAdapter(
    context: Context,
    private val session: PocketCameraSession,
    val library: MonitorMediaLibraryModel<LunaMediaLibraryPayload>,
    val cameraId: String,
    private val cache: MediaCache,
) {
    private val appContext = context.applicationContext
    val isLive: Boolean get() = library.canRefresh && session.phaseFlow.value ==
        com.opencapture.opencine.insta360.shell.ConnectionPhase.LIVE
    val mediaRoute get() = session.profile.media
    val downloadProgress: Map<String, Double> get() = library.state.value.records.mapNotNull { record ->
        library.state.value.progress[record.asset.id]?.let { record.payload.file.path to it }
    }.toMap()
    fun record(file: MediaFile): MonitorMediaRecord<LunaMediaLibraryPayload>? {
        val content = file.copy(isStarred = false)
        return library.state.value.records.firstOrNull { it.payload.file.copy(isStarred = false) == content }
    }
    fun isDownloaded(file: MediaFile): Boolean = record(file)?.let { library.state.value.entries[it.asset.id]?.original != null }
        ?: cache.isDownloaded(file, cameraId)
    fun isAvailableOffline(file: MediaFile): Boolean = record(file)?.let { library.state.value.entries[it.asset.id]?.isPlayableOffline == true }
        ?: cache.isAvailableOffline(file, cameraId)
    fun localFile(file: MediaFile): File? = cache.existingFile(cache.fileCache(cameraId, file))
    fun localPlaybackFile(file: MediaFile): File? = cache.localPlaybackFile(file, cameraId)
    fun thumbnailFile(file: MediaFile): File? = cache.existingFile(cache.thumbnailFile(cameraId, file))
    fun cacheGrade(file: MediaFile): MediaCacheGrade {
        val record = record(file) ?: return cache.cacheGrade(file, cameraId)
        val entry = library.state.value.entries[record.asset.id]
        return MediaCacheGrade.resolve(entry?.original != null, entry?.proxy != null)
    }
    fun cachedShotColor(file: MediaFile): Int = cache.shotColor(file.path, cameraId, appContext)
    fun fetchShotColor(file: MediaFile): Int {
        localFile(file)?.let { original ->
            val mode = ClipColorProfile.shotColorFromFile(original, file.path)
            if (mode >= 0) { cache.rememberShotColor(file.path, mode, cameraId); return mode }
        }
        val cached = cachedShotColor(file)
        if (cached >= 0) return cached
        val gamma = record(file)?.payload?.source?.gamma?.lowercase(Locale.US) ?: return -1
        val mode = when {
            "log" in gamma -> CameraCommands.COLOR_ILOG
            "dolby" in gamma || "hdr" in gamma -> CameraCommands.COLOR_DOLBY_VISION
            "standard" in gamma || "vivid" in gamma -> CameraCommands.COLOR_NORMAL
            else -> -1
        }
        if (mode >= 0) cache.rememberShotColor(file.path, mode, cameraId)
        return mode
    }
    fun isFavorite(file: MediaFile): Boolean = record(file)?.favorite ?: file.isStarred
    fun toggleFavorite(file: MediaFile) { record(file)?.let { library.toggleFavorite(it.asset.id) } }
    fun canCache(file: MediaFile): Boolean = isLive && library.canTransfer && record(file)?.asset?.representations?.any { it.role == MediaRepresentationRole.ORIGINAL } == true
    fun canDelete(file: MediaFile): Boolean = isLive && library.canDelete && record(file)?.asset?.deletable == true
    suspend fun delete(file: MediaFile) {
        try { record(file)?.let { library.delete(listOf(it.asset.id)) } }
        catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (_: Exception) { session.presentControlNote(MediaOperatorCopy.DELETE_FAILED) }
    }
    suspend fun ensureThumbnail(file: MediaFile) = withContext(Dispatchers.Main.immediate) {
        record(file)?.let { library.ensureThumbnailAndWait(it.asset.id) }
    }
    suspend fun download(file: MediaFile) {
        try { record(file)?.let { library.cacheOriginal(it.asset.id) } }
        catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (_: Exception) { /* The common operation publishes its fenced failure note. */ }
    }
    fun playbackCandidates(record: MonitorMediaRecord<LunaMediaLibraryPayload>): List<MonitorPlaybackCandidate> {
        val file = record.payload.file
        val choices = mutableListOf<MonitorPlaybackCandidate>()
        cache.localProxyFile(file, cameraId)?.let { proxy ->
            choices += MonitorPlaybackCandidate.Cached(MonitorPlaybackItem(proxy.toURI(), MediaHTTP.playbackMIMEType(proxy.name),
                file.proxyPath ?: proxy.name, MediaRepresentationRole.PROXY))
        }
        if (isLive) record.asset.representations.filter { it.role == MediaRepresentationRole.PROXY }.forEach {
            choices += MonitorPlaybackCandidate.Representation(it.id, MediaHTTP.playbackMIMEType(file.proxyPath ?: "proxy.mp4"), file.proxyPath ?: file.path)
        }
        localFile(file)?.let { original ->
            choices += MonitorPlaybackCandidate.Cached(MonitorPlaybackItem(original.toURI(), MediaHTTP.playbackMIMEType(file.path), file.path))
        }
        if (isLive) record.asset.representations.firstOrNull { it.role == MediaRepresentationRole.ORIGINAL }?.let {
            choices += MonitorPlaybackCandidate.Representation(it.id, MediaHTTP.playbackMIMEType(file.path), file.path)
        }
        return choices
    }
    suspend fun resolvePlaybackLook(record: MonitorMediaRecord<LunaMediaLibraryPayload>): MonitorPlaybackLook<LunaPlaybackLook> {
        val file = record.payload.file
        val gamma = record.payload.source?.gamma?.lowercase(Locale.US)
        val original = localFile(file)
        val cached = cachedShotColor(file).takeIf { it >= 0 }
        val color = withContext(Dispatchers.IO) {
            original?.let { ClipColorProfile.shotColorFromFile(it, file.path).takeIf { mode -> mode >= 0 } }
                ?: cached ?: when {
                    gamma == null -> null
                    "log" in gamma -> CameraCommands.COLOR_ILOG
                    "dolby" in gamma || "hdr" in gamma -> CameraCommands.COLOR_DOLBY_VISION
                    "standard" in gamma || "vivid" in gamma -> CameraCommands.COLOR_NORMAL
                    else -> null
                }
        }
        val transfer = color?.let { com.opencapture.openpocketcine.feed.MonitorTransfer.fromColorMode(it) }
        return MonitorPlaybackLook(transfer, LunaPlaybackLook(color, file))
    }
    fun rememberPlaybackLook(look: LunaPlaybackLook) {
        look.colorMode?.let { cache.rememberShotColor(look.file.path, it, cameraId) }
    }
    /** Photo viewer compatibility while delivery/photo composition remains outside I5b-1. */
    suspend fun cacheForPlayback(file: MediaFile): File? {
        cache.localProxyFile(file, cameraId)?.let { return it }
        val record = record(file)
        if (isLive && record != null) {
            for (proxy in record.asset.representations.filter { it.role == MediaRepresentationRole.PROXY }) {
                try { return library.cacheRepresentation(proxy.id, record.asset.id) }
                catch (error: kotlinx.coroutines.CancellationException) { throw error }
                catch (_: Exception) { /* Preserve the source's proxy-to-original fallback. */ }
            }
        }
        localFile(file)?.let { return it }
        if (!isLive || record == null) return null
        return try { library.cacheOriginal(record.asset.id) }
        catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (_: Exception) { null }
    }
}
