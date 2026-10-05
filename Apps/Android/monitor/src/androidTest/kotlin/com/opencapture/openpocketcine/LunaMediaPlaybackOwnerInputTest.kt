package com.opencapture.openpocketcine

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.media.MediaMetadataRetriever
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.accessibilityservice.AccessibilityServiceInfo
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.media.*
import com.opencapture.openpocketcine.media.*
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** SIMULATED catalog source, real cached MP4, production gallery/player and native input. */
@RunWith(AndroidJUnit4::class)
class LunaMediaPlaybackOwnerInputTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    @Before fun installActualBackend() {
        MonitorConfiguration.install(MonitorConfiguration.identity) { context ->
            val wifi = com.opencapture.openpocketcine.pairing.CameraWifiCredentialStore(context)
            com.opencapture.opencine.insta360.luna.LunaBackend(context,
                savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove)
        }
    }

    /** SIMULATED input diagnosis only: real public retrievers, no gallery/player or UI input. */
    @Test fun nativeFixtureMetadataInitializationDiagnostic() {
        val base = instrumentation.targetContext.applicationContext
        val inputDirectory = File(checkNotNull(InstrumentationRegistry.getArguments().getString("playbackFixtureDir")))
        val manifest = JSONObject(File(inputDirectory, "manifest.json").readText()).getJSONArray("files")
        assertEquals(2, manifest.length())
        val copies = File(base.cacheDir, "playback-metadata-diagnostic." + UUID.randomUUID()).apply { mkdirs() }
        val evidence = File(instrumentation.targetContext.getExternalFilesDir(null), "i5b-playback-native-proof").apply { mkdirs() }
        val results = JSONArray()
        fun digest(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes())
            .joinToString("") { "%02x".format(it) }
        try {
            for (index in 0..1) {
                val name = if (index == 0) "A" else "B"
                val declared = manifest.getJSONObject(index)
                val original = File(inputDirectory, "Playback$name.mp4")
                assertEquals(name, declared.getString("name"))
                assertEquals(12, declared.getInt("duration")); assertEquals(640, declared.getInt("width"))
                assertEquals(360, declared.getInt("height")); assertEquals(24, declared.getInt("fps"))
                assertEquals(declared.getString("sha256"), digest(original))
                assertEquals(declared.getInt("size").toLong(), original.length())
                val copy = original.copyTo(File(copies, original.name))
                assertEquals(digest(original), digest(copy)); assertEquals(original.length(), copy.length())
                var admitted = false
                for ((mode, source) in listOf("original-path" to original, "original-fd" to original,
                    "private-path" to copy, "private-fd" to copy)) {
                    val result = JSONObject().put("input", name).put("mode", mode).put("path", source.absolutePath)
                        .put("bytes", source.length()).put("sha256", digest(source))
                    val metadata = MediaMetadataRetriever()
                    var frame: Bitmap? = null
                    try {
                        if (mode.endsWith("-fd")) {
                            FileInputStream(source).use { stream ->
                                assertEquals(0L, stream.channel.position())
                                metadata.setDataSource(stream.fd, 0, source.length())
                            }
                            // The documented public contract permits closing the descriptor here.
                        } else metadata.setDataSource(source.absolutePath)
                        result.put("setDataSourceReturned", true)
                        for ((key, field) in listOf(MediaMetadataRetriever.METADATA_KEY_DURATION to "duration",
                            MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH to "width",
                            MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT to "height",
                            MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE to "captureRate")) {
                            result.put(field, metadata.extractMetadata(key) ?: JSONObject.NULL)
                        }
                        frame = metadata.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)
                        result.put("nativeFrame", frame != null)
                        frame?.let { bitmap ->
                            result.put("frameWidth", bitmap.width).put("frameHeight", bitmap.height)
                            result.put("knownPattern", matches(bitmap, name))
                            File(evidence, "metadata-$name-$mode.png").outputStream().use {
                                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                            }
                        }
                        val captureRate = if (result.isNull("captureRate")) null else result.getString("captureRate")
                        val complete = result.optString("duration") == "12000" && result.optString("width") == "640" &&
                            result.optString("height") == "360" && frame?.width == 640 && frame?.height == 360 &&
                            result.optBoolean("knownPattern") && (captureRate == null || captureRate.toFloatOrNull() == 24f)
                        result.put("completeRequiredNativeFacts", complete)
                        admitted = admitted || complete
                    } catch (failure: Exception) {
                        result.put("errorType", failure.javaClass.name).put("error", failure.message ?: JSONObject.NULL)
                    } finally {
                        frame?.recycle(); metadata.release()
                        results.put(result)
                        File(evidence, "metadata-diagnostic.json").writeText(JSONObject()
                            .put("label", "SIMULATED native input diagnosis; no player or UI flow")
                            .put("results", results).toString(2))
                    }
                }
                assertTrue(admitted, "No native source mode reports the unchanged 12s/640x360 and real expected frame for $name")
            }
        } finally { copies.deleteRecursively() }
    }

    @Test fun actualPlayerTransportCoversRotationAndBackBorrowOneLibrary() {
        val base = instrumentation.targetContext.applicationContext
        val inputDirectory = File(checkNotNull(InstrumentationRegistry.getArguments().getString("playbackFixtureDir")))
        val manifest = JSONObject(File(inputDirectory, "manifest.json").readText()).getJSONArray("files")
        assertEquals(2, manifest.length())
        val domain = "playback-owner." + UUID.randomUUID()
        val root = File(base.cacheDir, domain)
        val domains = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getNoBackupFilesDir(): File = root
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val key = "$domain.$name"; domains += key
                return base.getSharedPreferences(key, mode)
            }
        }
        val automation = instrumentation.uiAutomation
        val originalFlags = automation.serviceInfo.flags
        var model: AppModel? = null
        try {
            val cacheRoot = File(root, "OpenPocketCine/media/fixture")
            val files = (0..1).map { index ->
                val original = File(inputDirectory, "Playback${if (index == 0) "A" else "B"}.mp4")
                val facts = manifest.getJSONObject(index)
                assertEquals(if (index == 0) "A" else "B", facts.getString("name"))
                assertEquals(12, facts.getInt("duration")); assertEquals(640, facts.getInt("width"))
                assertEquals(360, facts.getInt("height")); assertEquals(24, facts.getInt("fps"))
                assertEquals(facts.getInt("size").toLong(), original.length())
                val digest = MessageDigest.getInstance("SHA-256").digest(original.readBytes()).joinToString("") { "%02x".format(it) }
                assertEquals(facts.getString("sha256"), digest)
                val input = original.copyTo(File(root, "inputs/${original.name}").apply { parentFile!!.mkdirs() })
                assertEquals(original.length(), input.length())
                val copiedDigest = MessageDigest.getInstance("SHA-256").digest(input.readBytes()).joinToString("") { "%02x".format(it) }
                assertEquals(digest, copiedDigest)
                val metadata = MediaMetadataRetriever()
                val thumbnail: Bitmap
                try {
                    metadata.setDataSource(input.absolutePath)
                    assertEquals("12000", metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION))
                    assertEquals("640", metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH))
                    assertEquals("360", metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT))
                    // Capture-rate metadata is optional. Known native values must agree with the
                    // generated/probed stream; absence never becomes a fabricated native report.
                    metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toFloat()?.let { assertEquals(24f, it) }
                    thumbnail = checkNotNull(metadata.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST))
                } finally { metadata.release() }
                val chronology = 2 - index
                val suffix = "14000${chronology}_00_00${chronology}"
                val file = MediaFile(path = "DCIM/VID_20261003_$suffix.MP4", thumbPath = "DCIM/IMG_20261003_$suffix.JPG",
                    sizeBytes = input.length(), durationSeconds = 12, resolution = "640x360", fps = 24,
                    proxyPath = if (index == 0) "DCIM/LRV_20261003_$suffix.LRV" else null)
                val record = LunaMediaCatalogCodec(null) { null }.decode(JSONArray().put(file.toJson()).toString().toByteArray()).single()
                record.address.representations.values.forEach { address ->
                    File(cacheRoot, address).apply { parentFile!!.mkdirs(); input.copyTo(this) }
                }
                try {
                    File(cacheRoot, record.address.thumbnail).apply { parentFile!!.mkdirs() }.outputStream().use {
                        assertTrue(thumbnail.compress(Bitmap.CompressFormat.JPEG, 90, it))
                    }
                } finally { thumbnail.recycle() }
                file
            }
            File(cacheRoot, "index.json").writeText(JSONArray().apply { files.forEach { put(it.toJson()) } }.toString())
            context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE).edit()
                .putString("opc.media.lastCameraID", "fixture").commit()
            automation.serviceInfo = automation.serviceInfo.apply { flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS }
            ActivityScenario.launch(MonitorPreviewActivity::class.java).use { scenario ->
                val source = PlaybackGallerySource()
                var closed = 0
                scenario.onActivity { activity ->
                    model = AppModel(context)
                    model!!.mediaLibrary.bind(source)
                    activity.setContent { OpenPocketCineTheme { MediaLibraryScreen(model!!) { closed += 1 } } }
                    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                await("One actual browse opens") { source.opens == 1 && model!!.mediaLibrary.binding != null && model!!.mediaLibrary.state.value.records.size == 2 }
                val library = model!!.mediaLibrary
                assertEquals(files.map { it.filename }, library.displayedRecords.map { it.asset.filename },
                    "Actual displayed video order must put A before its Next B")
                val binding = library.binding
                val lifetime = library.state.value.lifetimeToken
                fun borrowed() {
                    assertTrue(model!!.mediaLibrary === library)
                    assertEquals(binding, library.binding); assertEquals(lifetime, library.state.value.lifetimeToken)
                    assertEquals(1, source.opens); assertEquals(0, source.browse.closes); assertTrue(library.state.value.browsing)
                }
                tap(files[0].filename)
                await("Actual A decoder renders") { pictureMatches(scenario, "A") && node("Pause") != null && progress() > 0f }
                // Loop and Pause before the evidence capture: on a loaded emulator the capture can
                // outlast the 12 s clip, and a pause near 3 s lets the paused scrub below accept
                // before its own seek frame lands.
                tap("Loop clip")
                tap("Pause")
                await("Actual native pause reaches UI") { node("Play") != null }
                val first = checkNotNull(readPicture(scenario))
                val viewIdentity = first.view; val surfaceIdentity = first.surface
                first.bitmap.recycle()
                borrowed(); capture(scenario, "A-portrait", "A", false, source)
                scrub(0.25f)
                await("Paused native scrub reaches interior") {
                    kotlin.math.abs(progress() - 3f) < 0.5f && node("Play") != null && pictureAt(scenario, "A", 3f)
                }
                val held = progress()
                val heldPicture = checkNotNull(readPicture(scenario))
                val advanceDeadline = SystemClock.uptimeMillis() + 1000
                while (SystemClock.uptimeMillis() < advanceDeadline) {
                    assertTrue(kotlin.math.abs(progress() - held) < 0.4f, "Paused native position must remain held")
                    settle()
                }
                val still = checkNotNull(readPicture(scenario))
                assertTrue(changedPixels(heldPicture.bitmap, still.bitmap) < 8, "Paused decoder image must remain held")
                heldPicture.bitmap.recycle()
                tap("Play")
                await("Actual native clock resumes") { progress() > held + 0.5f && node("Pause") != null }
                val resumed = checkNotNull(readPicture(scenario))
                try { assertTrue(changedPixels(still.bitmap, resumed.bitmap) > 16, "Actual decoded moving marker must advance after Play") }
                finally { still.bitmap.recycle(); resumed.bitmap.recycle() }
                scrub(0.5f)
                await("Playing final native seek resumes") { progress() in 5.5f..8f && node("Pause") != null }
                tap("Clip info"); await("Actual info cover appears") { node("Close clip information") != null }
                borrowed(); assertPictureIdentity(scenario, viewIdentity, surfaceIdentity)
                tap("Close clip information")
                tap("Share clip"); await("Actual Share cover appears") { node("Nearby Share, Files, and other apps") != null }
                borrowed(); assertPictureIdentity(scenario, viewIdentity, surfaceIdentity)
                tap("Close"); await("Donor Share return stays paused") { node("Play") != null }
                for (orientation in listOf(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE, ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)) {
                    scenario.onActivity { it.requestedOrientation = orientation }
                    val landscape = orientation != ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    await("Native orientation and picture settle") {
                        var oriented = false
                        scenario.onActivity { oriented = (it.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) == landscape }
                        oriented && pictureMatches(scenario, "A") && node("Next clip") != null
                    }
                    assertPictureIdentity(scenario, viewIdentity, surfaceIdentity); borrowed()
                    capture(scenario, "A-orientation-$orientation", "A", landscape, source)
                }
                tap("Next clip")
                await("Actual native B replaces A") { pictureMatches(scenario, "B") && node(files[1].filename) != null }
                borrowed(); capture(scenario, "B-portrait", "B", false, source)
                if (node("Pause") != null) tap("Pause")
                await("B pauses") { node("Play") != null }
                scrub(0.95f)
                await("B native seek reaches end region") { progress() > 10.8f && node("Play") != null }
                tap("Play")
                await("Loop restarts actual same B picture") { progress() < 2f && node("Pause") != null && pictureMatches(scenario, "B") }
                tap("Back to media")
                await("Player Back returns gallery and detaches native picture") { node(files[0].filename) != null && !hasPicture(scenario) }
                borrowed()
                instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
                await("Outer Back closes one actual browse") { closed == 1 && source.browse.closes == 1 }
                assertFalse(library.state.value.browsing); assertEquals(null, library.binding); assertEquals(1, source.opens)
                assertFalse(hasPicture(scenario))
                scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT; model!!.close() }
            }
        } finally {
            instrumentation.runOnMainSync { model?.close() }
            automation.serviceInfo = automation.serviceInfo.apply { flags = originalFlags }
            domains.forEach { base.deleteSharedPreferences(it) }; root.deleteRecursively()
            assertFalse(root.exists(), "Test-owned private input/cache root must be removed even after setup refusal")
        }
    }

    private data class Picture(val bitmap: Bitmap, val view: Int, val surface: Int)
    private fun readPicture(scenario: ActivityScenario<MonitorPreviewActivity>): Picture? {
        var result: Picture? = null
        fun find(view: View): TextureView? {
            if (view is TextureView && view.isAvailable && view.isShown && view.width > 1 && view.height > 1) return view
            if (view is ViewGroup) for (index in 0 until view.childCount) find(view.getChildAt(index))?.let { return it }
            return null
        }
        scenario.onActivity { activity ->
            find(activity.window.decorView)?.let { view ->
                view.getBitmap(160, 90)?.let { bitmap ->
                    result = Picture(bitmap, System.identityHashCode(view), System.identityHashCode(view.surfaceTexture))
                }
            }
        }
        return result
    }
    private fun matches(bitmap: Bitmap, pattern: String, minimumFraction: Float = 0.5f): Boolean {
        var count = 0
        for (y in 0 until bitmap.height step 2) for (x in 0 until bitmap.width step 2) {
            val color = bitmap.getPixel(x, y)
            val r = Color.red(color); val g = Color.green(color); val b = Color.blue(color)
            if (if (pattern == "A") r < 60 && g > 90 && b < 65 else r < 60 && g < 70 && b > 130) count += 1
        }
        return count > bitmap.width * bitmap.height / 4 * minimumFraction
    }
    private fun pictureMatches(scenario: ActivityScenario<MonitorPreviewActivity>, pattern: String): Boolean {
        val picture = readPicture(scenario) ?: return false
        return try { matches(picture.bitmap, pattern) } finally { picture.bitmap.recycle() }
    }
    private fun hasPicture(scenario: ActivityScenario<MonitorPreviewActivity>): Boolean {
        val picture = readPicture(scenario) ?: return false
        picture.bitmap.recycle(); return true
    }
    /** Independent encoded marker moves at 35 source pixels/second in the generated input. */
    private fun pictureAt(scenario: ActivityScenario<MonitorPreviewActivity>, pattern: String, seconds: Float): Boolean {
        val picture = readPicture(scenario) ?: return false
        return try {
            if (!matches(picture.bitmap, pattern)) false else {
                val bitmap = picture.bitmap
                var left = bitmap.width
                for (y in 31..51) for (x in 0 until bitmap.width) {
                    val color = bitmap.getPixel(x, y)
                    val background = if (pattern == "A") Color.red(color) < 60 && Color.green(color) > 90 && Color.blue(color) < 65
                        else Color.red(color) < 60 && Color.green(color) < 70 && Color.blue(color) > 130
                    if (!background) left = minOf(left, x)
                }
                kotlin.math.abs(left - (40f + seconds * 35f) / 4f) < 4f
            }
        } finally { picture.bitmap.recycle() }
    }
    private fun changedPixels(first: Bitmap, second: Bitmap): Int {
        assertEquals(first.width, second.width); assertEquals(first.height, second.height)
        var count = 0
        for (y in 0 until first.height step 2) for (x in 0 until first.width step 2) {
            val a = first.getPixel(x, y); val b = second.getPixel(x, y)
            if (kotlin.math.abs(Color.red(a) - Color.red(b)) + kotlin.math.abs(Color.green(a) - Color.green(b)) + kotlin.math.abs(Color.blue(a) - Color.blue(b)) > 30) count += 1
        }
        return count
    }
    private fun assertPictureIdentity(scenario: ActivityScenario<MonitorPreviewActivity>, view: Int, surface: Int) {
        val picture = checkNotNull(readPicture(scenario))
        try { assertEquals(view, picture.view); assertEquals(surface, picture.surface) } finally { picture.bitmap.recycle() }
    }
    private fun capture(scenario: ActivityScenario<MonitorPreviewActivity>, name: String, pattern: String, landscape: Boolean, source: PlaybackGallerySource) {
        val folder = File(instrumentation.targetContext.getExternalFilesDir(null), "i5b-playback-native-proof").apply { mkdirs() }
        val picture = checkNotNull(readPicture(scenario))
        try {
            assertTrue(matches(picture.bitmap, pattern))
            File(folder, "$name-texture.png").outputStream().use { assertTrue(picture.bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            var screenshot: Bitmap? = null
            await("Actual native window presents decoded $pattern in the settled orientation") {
                if (screenshot != null) return@await true
                val candidate = instrumentation.uiAutomation.takeScreenshot() ?: return@await false
                if ((candidate.width > candidate.height) == landscape && matches(candidate, pattern, 0.1f)) {
                    screenshot = candidate; true
                } else { candidate.recycle(); false }
            }
            val accepted = checkNotNull(screenshot)
            try {
                assertEquals(landscape, accepted.width > accepted.height)
                File(folder, "$name-window.png").outputStream().use { assertTrue(accepted.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            } finally { accepted.recycle() }
            File(folder, "$name-native.json").writeText(JSONObject().apply {
                put("label", "SIMULATED actual native player"); put("pattern", pattern); put("view", picture.view)
                put("surface", picture.surface); put("position", progress()); put("opens", source.opens); put("closes", source.browse.closes)
            }.toString(2))
        } finally { picture.bitmap.recycle() }
    }
    private fun settle() { instrumentation.waitForIdleSync(); SystemClock.sleep(60) }
    private fun await(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 10000
        while (!condition() && SystemClock.uptimeMillis() < deadline) settle()
        val accepted = condition()
        if (!accepted) {
            val folder = File(instrumentation.targetContext.getExternalFilesDir(null), "i5b-playback-native-proof").apply { mkdirs() }
            File(folder, "failure-observation.txt").writeText("$message\nposition=${progress()}\nwindows=" +
                instrumentation.uiAutomation.windows.joinToString { window ->
                    val bounds = Rect(); window.getBoundsInScreen(bounds); "${window.id}:$bounds"
                })
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try { File(folder, "UNACCEPTED-failure-window.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
                finally { bitmap.recycle() }
            }
        }
        assertTrue(accepted, message)
    }
    private fun node(label: String): AccessibilityNodeInfo? {
        fun find(value: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (value == null) return null
            if (value.isVisibleToUser && (value.contentDescription?.toString() == label || value.text?.toString() == label)) return value
            for (index in 0 until value.childCount) find(value.getChild(index))?.let { return it }
            return null
        }
        val automation = instrumentation.uiAutomation
        for (window in automation.windows.sortedByDescending { it.layer }) find(window.root)?.let { return it }
        return find(automation.rootInActiveWindow)
    }
    private fun bounds(label: String): Rect {
        await("Actual native target is visible: $label") { node(label) != null }
        return Rect().also { checkNotNull(node(label)).getBoundsInScreen(it); assertFalse(it.isEmpty) }
    }
    // Compose posts semantics changes only to enabled accessibility services, never to this
    // UiAutomation client, so a cached position goes stale after a paused seek: refresh it.
    private fun progress(): Float = node("Playback position")?.apply { refresh() }?.rangeInfo?.current ?: Float.NaN
    private fun tap(label: String) {
        val rect = bounds(label); val down = SystemClock.uptimeMillis()
        pointer(MotionEvent.ACTION_DOWN, rect.exactCenterX(), rect.exactCenterY(), down)
        SystemClock.sleep(40); pointer(MotionEvent.ACTION_UP, rect.exactCenterX(), rect.exactCenterY(), down); settle()
    }
    private fun scrub(fraction: Float) {
        val rect = bounds("Playback position"); assertTrue(rect.width() > 100)
        val down = SystemClock.uptimeMillis(); val y = rect.exactCenterY()
        pointer(MotionEvent.ACTION_DOWN, rect.left + rect.width() * 0.1f, y, down)
        SystemClock.sleep(40)
        pointer(MotionEvent.ACTION_MOVE, rect.left + rect.width() * fraction, y, down)
        SystemClock.sleep(40)
        pointer(MotionEvent.ACTION_UP, rect.left + rect.width() * fraction, y, down); settle()
    }
    private fun pointer(action: Int, x: Float, y: Float, down: Long) {
        val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0)
        try { assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true)) } finally { event.recycle() }
    }
    private class PlaybackGallerySource : CameraMediaService {
        val browse = PlaybackGalleryBrowse(); var opens = 0
        override val sessionID = browse.binding.session
        override suspend fun openBrowse(): CameraMediaBrowse { opens += 1; return browse }
    }
    private class PlaybackGalleryBrowse : CameraMediaBrowse {
        override val binding = MediaBrowseBinding(CameraSessionID(), ControlEpoch(1))
        override val thumbnails: CameraMediaThumbnailService? = null
        override val transfers: CameraMediaTransferService? = null
        override val deletion: CameraMediaDeleteService? = null
        var closes = 0
        override suspend fun catalog(): MediaCatalogCursor = object : MediaCatalogCursor {
            var done = false
            override suspend fun next(): MediaCatalogDelta? = if (done) null else MediaCatalogDelta(complete = true).also { done = true }
            override fun close() { done = true }
        }
        override suspend fun close() { closes += 1 }
    }
}
