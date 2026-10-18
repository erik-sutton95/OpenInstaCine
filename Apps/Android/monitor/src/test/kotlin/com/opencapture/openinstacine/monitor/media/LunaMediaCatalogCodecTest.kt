package com.opencapture.openinstacine.monitor.media

import android.content.SharedPreferences
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.insta360.luna.LunaMediaCatalogRecord
import com.opencapture.opencine.insta360.luna.LunaMediaCatalogRecordSource
import com.opencapture.opencine.insta360.shell.CameraMediaItem
import com.opencapture.opencine.media.*
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraLabelProfile
import com.opencapture.openinstacine.monitor.session.CameraProfile
import kotlinx.coroutines.test.runTest
import org.json.JSONArray
import org.json.JSONObject
import java.lang.reflect.Proxy
import java.nio.file.Files
import kotlin.test.*
import com.opencapture.opencine.vocabulary.MediaFile

class LunaMediaCatalogCodecTest {
    private fun file(starred: Boolean = false, storage: Int = 0) = MediaFile(
        path = "/storage_internal/DCIM/Camera01/VID_20260916_124229_002.mp4",
        thumbPath = "/storage_internal/DCIM/Camera01/thumb.jpg", handle = 1, cmdHandle = 27,
        sizeBytes = 99, durationSeconds = 7, isStarred = starred, resolution = "1920x1080", fps = 30,
        proxyPath = "/storage_internal/DCIM/Camera01/LRV_20260916_124229_002.lrv", storage = storage,
        storageKnown = false, group = 4, handleShared = true)
    private fun bytes(files: List<MediaFile>): ByteArray = JSONArray().apply { files.forEach { put(it.toJson()) } }
        .toString().toByteArray()
    @Test fun legacyUnknownShotColorStaysStoredButIsOmittedFromFilterOptions() {
        val root = Files.createTempDirectory("luna-color-options-").toFile()
        try {
            val preferences = Proxy.newProxyInstance(SharedPreferences::class.java.classLoader,
                arrayOf(SharedPreferences::class.java)) { _, method, _ ->
                throw AssertionError("Unexpected preferences access: ${method.name}")
            } as SharedPreferences
            val cache = MediaCache(root, preferences, MonitorMediaCacheStorage())
            val cameraID = "saved-camera"
            val unknown = 65_534
            val custom = 65_535
            val stored = listOf(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_ILOG, unknown, custom)
                .associate { mode -> file().copy(path = "/saved/$mode.mp4") to mode }
            val colors = JSONObject().apply { stored.forEach { (file, mode) -> put(file.path, mode) } }
                .toString().toByteArray()
            val colorFile = java.io.File(cache.cacheRoot(cameraID), "color.json")
            colorFile.parentFile!!.mkdirs(); colorFile.writeBytes(colors)
            val codec = LunaMediaCatalogCodec(null) { file -> cache.shotColor(file.path, cameraID).takeIf { it >= 0 } }
            val index = bytes(stored.keys.toList())
            val records = codec.decode(index)
            assertEquals(unknown.toString(), records.single { stored[it.payload.file] == unknown }.facts.color)
            val profile = CameraProfile(CameraLabelProfile(colorModeLabels = mapOf(CameraCommands.COLOR_NORMAL to "Standard", custom to "Custom log")))
            val facts = records.map { it.facts.color }
            assertEquals(listOf(CameraCommands.COLOR_NORMAL to "Standard", custom to "Custom log",
                CameraCommands.COLOR_ILOG to "I-Log"), mediaColorOptions(facts + facts + listOf(null, "unknown"), profile))
            assertContentEquals(index, codec.encode(records))
            assertContentEquals(colors, colorFile.readBytes())
        } finally { root.deleteRecursively() }
    }
    @Test fun legacyBytesFieldsAndAddressesStayCompatible() {
        val codec = LunaMediaCatalogCodec(null) { null }
        val original = bytes(listOf(file()))
        val record = codec.decode(original).single()
        assertContentEquals(original, codec.encode(listOf(record)))
        assertEquals(file(), record.payload.file); assertNull(record.payload.source)
        assertEquals(file().path, record.address.favoriteKey)
        assertEquals("thumbs/_storage_internal_DCIM_Camera01_thumb.jpg.jpg", record.address.thumbnail)
        val id = record.asset.representations.first { it.role == MediaRepresentationRole.ORIGINAL }.id
        assertEquals("files/_storage_internal_DCIM_Camera01_VID_20260916_124229_002.mp4", record.address.representations[id])
        assertEquals("20260916", record.facts.dateKey); assertEquals("20260916124229", record.facts.orderKey)
    }
    @Test fun loadingUnknownRawFieldsNeverRewritesIndex() {
        val root = Files.createTempDirectory("luna-codec-").toFile()
        try {
            val directory = MonitorMediaCacheDirectory(root)
            val codec = LunaMediaCatalogCodec(null) { null }
            val cache = MonitorMediaCache(directory, codec, MonitorMediaOriginalEligibility.ExactSize,
                "index.json", listOf("index.json", "color.json"))
            val preserved = bytes(listOf(file())).toString(Charsets.UTF_8)
                .replace("[{", "[{\"unknownRaw\":{\"code\":19},").toByteArray()
            directory.write(preserved, "index.json")
            assertEquals(listOf(file()), cache.load().map { it.payload.file })
            assertContentEquals(preserved, directory.read("index.json"))
        } finally { root.deleteRecursively() }
    }
    @Test fun offlineContentIdentitySeparatesVolumesAndIgnoresLocalFavoriteChanges() {
        val codec = LunaMediaCatalogCodec(null) { null }
        val ids = codec.decode(bytes(listOf(file(storage = 1), file(storage = 2)))).map { it.asset.id }
        assertNotEquals(ids[0], ids[1])
        assertEquals(codec.decode(bytes(listOf(file()))).single().asset.id,
            codec.decode(bytes(listOf(file(starred = true)))).single().asset.id)
    }
    @Test fun capturedRawPayloadSurvivesBrowseReplacementBeforeEncoding() {
        val binding = MediaBrowseBinding(CameraSessionID(), ControlEpoch(1))
        val id = MediaAssetID("opaque-A")
        val sourceFile = CameraMediaItem(file().path, sizeBytes = 99, durationSeconds = 7, width = 1920,
            height = 1080, fps = 30, gamma = "log")
        var current = binding
        var raw = sourceFile
        val source = object : LunaMediaCatalogRecordSource {
            override fun mediaCatalogRecord(asset: MediaAssetID, binding: MediaBrowseBinding) =
                if (binding == current && asset == id) LunaMediaCatalogRecord(asset, raw) else null
        }
        val codec = LunaMediaCatalogCodec(source) { null }
        val asset = MediaAsset(id = id, filename = "A.mp4", representations = listOf(
            MediaRepresentation(MediaRepresentationID("original-A"), MediaRepresentationRole.ORIGINAL, 99)))
        val captured = codec.capture(asset, binding)
        current = binding.copy(lease = java.util.UUID.randomUUID())
        raw = sourceFile.copy(sizeBytes = 1000, gamma = "standard")
        assertEquals(sourceFile, captured.payload.source)
        assertEquals(99L, JSONArray(codec.encode(listOf(captured)).toString(Charsets.UTF_8)).getJSONObject(0).getLong("sizeBytes"))
        assertFailsWith<MediaServiceException> { codec.capture(asset, binding) }
    }
    @Test fun unfavoriteSurvivesLegacyCatalogReload() = runTest {
        val root = Files.createTempDirectory("luna-favorite-").toFile()
        val favorites = object : MonitorMediaFavoritesStore {
            var values = emptySet<String>()
            override fun favorites() = values
            override fun saveFavorites(keys: Set<String>) { values = keys }
        }
        val codec = LunaMediaCatalogCodec(null) { null }
        val cache = MonitorMediaCache(MonitorMediaCacheDirectory(root), codec, MonitorMediaOriginalEligibility.ExactSize,
            "index.json", listOf("index.json", "color.json"))
        cache.directory.write(bytes(listOf(file(starred = true))), "index.json")
        val original = MonitorMediaLibraryModel(cache, favorites, scope = backgroundScope)
        try {
            val id = original.state.value.records.single().asset.id
            original.toggleFavorite(id); original.close()
            val reloaded = MonitorMediaLibraryModel(cache, favorites, scope = backgroundScope)
            try { assertFalse(reloaded.state.value.records.single().favorite) } finally { reloaded.dispose() }
        } finally { original.dispose(); root.deleteRecursively() }
    }
}
