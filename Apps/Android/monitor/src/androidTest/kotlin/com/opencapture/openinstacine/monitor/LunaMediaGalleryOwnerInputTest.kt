package com.opencapture.openinstacine.monitor

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.media.*
import com.opencapture.monitorui.MonitorMediaLayout
import com.opencapture.openinstacine.monitor.media.*
import com.opencapture.opencine.vocabulary.MediaFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** SIMULATED source, actual app factory/gallery/native input and cache namespaces. */
@RunWith(AndroidJUnit4::class)
class LunaMediaGalleryOwnerInputTest {
    @Before fun installActualBackend() {
        MonitorConfiguration.install(MonitorConfiguration.identity) { context ->
            val wifi = com.opencapture.opencine.platform.CameraWifiCredentialStore(context, com.opencapture.openinstacine.monitor.pairing.cameraWifiStorage)
            com.opencapture.opencine.insta360.luna.LunaBackend(context,
                savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove)
        }
    }
    @Test fun actualGalleryFavoritesSelectionAndBorrowedCoversKeepOneBrowseUntilNativeBack() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        val domain = "media-owner." + UUID.randomUUID()
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
        val files = (1..2).map { index -> MediaFile(
            path = "DCIM/IMG_20261003_14000${index}_00_00${index}.jpg",
            thumbPath = "DCIM/IMG_20261003_14000${index}_00_00${index}.jpg") }
        val image = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.GREEN) }
        val bytes = ByteArrayOutputStream().also { image.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        image.recycle()
        val cacheRoot = File(root, "OpenPocketCine/media/fixture")
        File(cacheRoot, "files").mkdirs()
        files.forEach { File(cacheRoot, "files/" + MediaCache.cacheName(it.path)).writeBytes(bytes) }
        File(cacheRoot, "index.json").writeText(JSONArray().apply { files.forEach { put(it.toJson()) } }.toString())
        context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE).edit()
            .putString("opc.media.lastCameraID", "fixture").commit()
        var model: AppModel? = null
        try {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                // The preceding native test may leave this shared host in landscape.
                // Admit the actual portrait configuration before mounting its portrait fixture.
                scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
                await {
                    var portrait = false
                    scenario.onActivity { portrait = it.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT }
                    portrait
                }
                val source = GallerySource()
                var closed = 0
                scenario.onActivity { activity ->
                    model = AppModel(context)
                    model!!.mediaLibrary.bind(source)
                    activity.setContent { MediaLibraryScreen(model!!) { closed += 1 } }
                }
                await { source.opens == 1 && model!!.mediaLibrary.binding != null }
                val owner = model!!.mediaLibrary
                val binding = owner.binding
                assertTrue(owner.state.value.records.size == 2)
                tap(scenario, "Add to favorites")
                await { owner.state.value.records.count { it.favorite } == 1 }
                val favorite = owner.state.value.records.first { it.favorite }
                assertTrue(context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE)
                    .getString("opc.media.fav.fixture", "")!!.contains(favorite.payload.file.path))
                tap(scenario, "Show Favorites media")
                await { owner.displayedRecords.size == 1 }
                tap(scenario, "Show All media")
                tap(scenario, "List view")
                await { owner.state.value.layout == MonitorMediaLayout.LIST }
                val target = bounds(files.first().filename)
                val down = SystemClock.uptimeMillis()
                pointer(scenario, MotionEvent.ACTION_DOWN, target.centerX().toFloat(), target.centerY().toFloat(), down)
                SystemClock.sleep(450)
                pointer(scenario, MotionEvent.ACTION_UP, target.centerX().toFloat(), target.centerY().toFloat(), down)
                await { owner.state.value.selecting && owner.state.value.selectedIDs.size == 1 }
                screenshot("portrait-selection", landscape = false, cellLabel = files.first().filename)
                scenario.onActivity { activity -> activity.setContent { Text("Borrowed native cover") } }
                settle()
                assertEquals(binding, owner.binding); assertEquals(0, source.browse.closes)
                scenario.onActivity { activity ->
                    activity.setContent { MediaLibraryScreen(model!!) { closed += 1 } }
                    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                }
                await {
                    var landscape = false
                    scenario.onActivity { landscape = it.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE }
                    landscape
                }
                // The outer owner survives recreation/rotation even when the native host is rebuilt.
                scenario.onActivity { activity -> activity.setContent { MediaLibraryScreen(model!!) { closed += 1 } } }
                settle()
                assertTrue(model!!.mediaLibrary === owner)
                assertEquals(binding, owner.binding); assertEquals(1, source.opens)
                assertEquals(1, owner.state.value.selectedIDs.size)
                screenshot("landscape-selection", landscape = true, cellLabel = files.first().filename)
                scenario.onActivity { owner.clearSelection() }
                settle()
                InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
                await { closed == 1 && source.browse.closes == 1 }
                assertFalse(owner.state.value.browsing); assertEquals(null, owner.binding)
                scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT; model!!.close() }
            }
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { model?.close() }
            domains.forEach { base.deleteSharedPreferences(it) }
            root.deleteRecursively()
        }
    }
    private fun screenshot(name: String, landscape: Boolean, cellLabel: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val folder = File(instrumentation.targetContext.getExternalFilesDir(null), "i5a-gallery-native-proof")
        assertTrue(folder.mkdirs() || folder.isDirectory)
        var rendered: Bitmap? = null
        var lastObservation = "No native window observed"
        // Configuration and model state can precede the native rotation's presented frame. This
        // independent fixture color proves the actual seeded JPEG is visible before accepting it.
        try { await {
            if (rendered != null) return@await true
            val root = instrumentation.uiAutomation.rootInActiveWindow ?: return@await false
            val cell = node(cellLabel) ?: return@await false
            val windowBounds = Rect().also { root.getBoundsInScreen(it) }
            val cellBounds = Rect().also { cell.getBoundsInScreen(it) }
            lastObservation = "expectedLandscape=$landscape window=$windowBounds cell=$cellBounds"
            if ((windowBounds.width() > windowBounds.height()) != landscape ||
                cellBounds.isEmpty || !Rect.intersects(windowBounds, cellBounds)) return@await false
            val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return@await false
            val oriented = (bitmap.width > bitmap.height) == landscape
            lastObservation += " screenshot=${bitmap.width}x${bitmap.height} oriented=$oriented"
            val fixtureVisible = oriented && (0 until bitmap.height step 8).any { y ->
                (0 until bitmap.width step 8).any { x ->
                    val pixel = bitmap.getPixel(x, y)
                    Color.red(pixel) < 30 && Color.green(pixel) > 200 && Color.blue(pixel) < 30
                }
            }
            lastObservation += " seededJpegVisible=$fixtureVisible"
            if (fixtureVisible) { rendered = bitmap; true } else { bitmap.recycle(); false }
        } } catch (failure: Throwable) {
            File(folder, "$name-failure-observation.txt").writeText(lastObservation)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try {
                    File(folder, "$name-unaccepted.png").outputStream().use {
                        assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                    }
                } finally { bitmap.recycle() }
            }
            throw failure
        }
        val bitmap = checkNotNull(rendered)
        try {
            File(folder, "$name.png").outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        } finally { bitmap.recycle() }
    }
    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(100)
    }
    private fun await(condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5000
        while (!condition() && SystemClock.uptimeMillis() < deadline) settle()
        assertTrue(condition(), "Actual gallery owner did not reach the expected state")
    }
    private fun node(label: String): AccessibilityNodeInfo? {
        fun find(value: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (value == null) return null
            if (value.contentDescription?.toString() == label || value.text?.toString() == label) return value
            for (index in 0 until value.childCount) find(value.getChild(index))?.let { return it }
            return null
        }
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
    }
    private fun bounds(label: String): Rect {
        await { node(label) != null }
        return Rect().also { checkNotNull(node(label)).getBoundsInScreen(it); assertFalse(it.isEmpty) }
    }
    private fun tap(scenario: ActivityScenario<BackdropRenderActivity>, label: String) {
        val bounds = bounds(label); val down = SystemClock.uptimeMillis()
        pointer(scenario, MotionEvent.ACTION_DOWN, bounds.centerX().toFloat(), bounds.centerY().toFloat(), down)
        SystemClock.sleep(40)
        pointer(scenario, MotionEvent.ACTION_UP, bounds.centerX().toFloat(), bounds.centerY().toFloat(), down)
        settle()
    }
    private fun pointer(scenario: ActivityScenario<BackdropRenderActivity>, action: Int, x: Float, y: Float, down: Long) {
        scenario.onActivity { activity ->
            val origin = IntArray(2); activity.window.decorView.getLocationOnScreen(origin)
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x - origin[0], y - origin[1], 0)
            try { assertTrue(activity.window.decorView.dispatchTouchEvent(event)) } finally { event.recycle() }
        }
    }
    private class GallerySource : CameraMediaService {
        val browse = GalleryBrowse()
        var opens = 0
        override val sessionID = browse.binding.session
        override suspend fun openBrowse(): CameraMediaBrowse { opens += 1; return browse }
    }
    private class GalleryBrowse : CameraMediaBrowse {
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
