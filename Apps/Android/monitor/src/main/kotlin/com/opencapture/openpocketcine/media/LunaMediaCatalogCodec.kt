package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.insta360.luna.LunaMediaCatalogRecordSource
import com.opencapture.opencine.insta360.shell.CameraMediaItem
import com.opencapture.opencine.media.*
import com.opencapture.openpocketcine.session.CameraCommands
import org.json.JSONObject
import org.json.JSONArray
import java.util.Base64
import java.util.Locale

/** Immutable source facts alongside the unchanged legacy index record. */
data class LunaMediaLibraryPayload(val file: MediaFile, val source: CameraMediaItem?)

/** App-owned legacy addressing/schema. The neutral library never interprets these source facts. */
class LunaMediaCatalogCodec(
    private val source: LunaMediaCatalogRecordSource?,
    private val shotColor: (MediaFile) -> Int?,
) : MonitorMediaCatalogCodec<LunaMediaLibraryPayload> {
    override fun decode(bytes: ByteArray): List<MonitorMediaRecord<LunaMediaLibraryPayload>> {
        val array = JSONArray(bytes.toString(Charsets.UTF_8))
        return (0 until array.length()).map { index ->
            val file = MediaFile.fromJson(array.getJSONObject(index))
            val content = file.copy(isStarred = false).toJson().toString().toByteArray(Charsets.UTF_8)
            val id = MediaAssetID("legacy-index:" + Base64.getEncoder().encodeToString(content))
            val representations = buildList {
                add(MediaRepresentation(MediaRepresentationID(id.rawValue + ":original"),
                    MediaRepresentationRole.ORIGINAL, file.sizeBytes.takeIf { it > 0 }))
                if (file.proxyPath != null) add(MediaRepresentation(MediaRepresentationID(id.rawValue + ":proxy"),
                    MediaRepresentationRole.PROXY))
            }
            record(MediaAsset(id = id, filename = file.filename,
                kind = if (file.kind == MediaKind.VIDEO) MediaAssetKind.VIDEO else MediaAssetKind.PHOTO,
                durationSeconds = file.durationSeconds.takeIf { it > 0 }?.toDouble(),
                frameRate = file.fps?.takeIf { it > 0 }?.toDouble(), representations = representations),
                LunaMediaLibraryPayload(file, null))
        }
    }
    override fun encode(records: List<MonitorMediaRecord<LunaMediaLibraryPayload>>): ByteArray {
        val array = JSONArray()
        records.forEach { array.put(it.payload.file.copy(isStarred = it.favorite).toJson()) }
        return array.toString().toByteArray(Charsets.UTF_8)
    }
    override fun capture(asset: MediaAsset, binding: MediaBrowseBinding): MonitorMediaRecord<LunaMediaLibraryPayload> {
        val captured = source?.mediaCatalogRecord(asset.id, binding)
            ?: throw MediaServiceException(MediaServiceFailure.RETIRED)
        val item = captured.file
        val file = MediaFile(path = item.path, thumbPath = item.path, handle = 1,
            sizeBytes = item.sizeBytes, durationSeconds = item.durationSeconds,
            resolution = if (item.width != null && item.height != null) "${item.width}x${item.height}" else null,
            fps = item.fps, proxyPath = item.proxyPath)
        return record(asset, LunaMediaLibraryPayload(file, item))
    }
    private fun record(asset: MediaAsset, payload: LunaMediaLibraryPayload): MonitorMediaRecord<LunaMediaLibraryPayload> {
        val file = payload.file
        val addresses = asset.representations.mapNotNull { representation ->
            when (representation.role) {
                MediaRepresentationRole.ORIGINAL -> representation.id to "files/" + cacheName(file.path)
                MediaRepresentationRole.PROXY -> file.proxyPath?.let {
                    representation.id to "play/" + MediaHTTP.playbackCacheFileName(it)
                }
            }
        }.toMap()
        val color = shotColor(file) ?: sourceColor(payload.source?.gamma)
        return MonitorMediaRecord(asset, payload, MonitorMediaCacheAddress(
            "thumbs/" + cacheName(file.thumbPath) + ".jpg", addresses, file.path), file.isStarred,
            MonitorMediaFilterFacts(file.fileExtension, file.resolution, file.dateKey.takeIf { it.isNotEmpty() },
                file.filenameTimestamp, color?.toString()))
    }
    private fun sourceColor(gamma: String?): Int? {
        val text = gamma?.lowercase(Locale.US) ?: return null
        return when {
            "log" in text -> CameraCommands.COLOR_ILOG
            "dolby" in text || "hdr" in text -> CameraCommands.COLOR_DOLBY_VISION
            "standard" in text || "vivid" in text -> CameraCommands.COLOR_NORMAL
            else -> null
        }
    }
    private fun cacheName(path: String): String = path.replace('/', '_')
}


internal fun MediaFile.toJson(): JSONObject =
    JSONObject().apply {
        put("path", path)
        put("thumbPath", thumbPath)
        put("handle", handle)
        put("cmdHandle", cmdHandle)
        put("sizeBytes", sizeBytes)
        put("durationSeconds", durationSeconds)
        put("isStarred", isStarred)
        if (resolution != null) put("resolution", resolution) else put("resolution", JSONObject.NULL)
        if (fps != null) put("fps", fps) else put("fps", JSONObject.NULL)
        if (proxyPath != null) put("proxyPath", proxyPath) else put("proxyPath", JSONObject.NULL)
        put("storage", storage)
        put("storageKnown", storageKnown)
        put("group", group)
        put("handleShared", handleShared)
    }

internal fun MediaFile.Companion.fromJson(obj: JSONObject): MediaFile =
    MediaFile(
        path = obj.optString("path"),
        thumbPath = obj.optString("thumbPath"),
        handle = obj.optLong("handle"),
        cmdHandle = obj.optLong("cmdHandle"),
        sizeBytes = obj.optLong("sizeBytes"),
        durationSeconds = obj.optInt("durationSeconds"),
        isStarred = obj.optBoolean("isStarred"),
        resolution = obj.optStringOrNull("resolution"),
        fps = if (obj.isNull("fps")) null else obj.optInt("fps"),
        proxyPath = obj.optStringOrNull("proxyPath"),
        storage = obj.optInt("storage"),
        storageKnown = obj.optBoolean("storageKnown", false),
        group = obj.optInt("group"),
        handleShared = obj.optBoolean("handleShared"),
    )

private fun JSONObject.optStringOrNull(key: String): String? {
    if (!has(key) || isNull(key)) return null
    val value = optString(key)
    return value.takeIf { it.isNotEmpty() }
}
