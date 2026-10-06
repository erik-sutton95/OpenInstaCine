package com.opencapture.openinstacine.monitor.media

import android.content.Context
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.CameraMediaService
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlinx.coroutines.CoroutineScope

/** Actual app composition: required legacy namespace, codec, preference keys and size policy. */
fun createLunaMediaLibrary(
    context: Context, session: PocketCameraSession, storage: MonitorMediaCacheStorage,
    service: CameraMediaService?, scope: CoroutineScope,
): Pair<MonitorMediaLibraryModel<LunaMediaLibraryPayload>, LunaMediaPlaybackAdapter> {
    val context = context.applicationContext
    val preferences = context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE)
    val key = session.connectedCamera?.id?.takeIf { it.isNotEmpty() }
        ?: preferences.getString("opc.media.lastCameraID", null) ?: "unknown"
    if (session.connectedCamera?.id?.takeIf { it.isNotEmpty() } != null &&
        preferences.getString("opc.media.lastCameraID", null) != key) {
        preferences.edit().putString("opc.media.lastCameraID", key).apply()
    }
    val look = MediaCache(context.noBackupFilesDir, preferences)
    val codec = LunaMediaCatalogCodec(session.mediaCatalogRecords) { file ->
        look.shotColor(file.path, key, context).takeIf { it >= 0 }
    }
    val cache = MonitorMediaCache(storage.directory(look.cacheRoot(key)), codec,
        MonitorMediaOriginalEligibility.ExactSize, "index.json", listOf("index.json", "color.json"))
    val favorites = MonitorMediaPreferences(preferences, "opc.media.fav.$key",
        "opc.media.lastCameraID", "\u001f")
    val library = MonitorMediaLibraryModel(cache, favorites, service, scope)
    return library to LunaMediaPlaybackAdapter(context, session, library, key, look)
}
