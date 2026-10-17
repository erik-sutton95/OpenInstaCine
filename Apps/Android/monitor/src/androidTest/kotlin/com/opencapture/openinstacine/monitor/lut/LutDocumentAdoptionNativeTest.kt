package com.opencapture.openinstacine.monitor.lut

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.compose.setContent
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.ActivityOptionsCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.cameracontrols.MonitorLutCategory
import com.opencapture.opencine.cameracontrols.MonitorLutLibrary
import com.opencapture.opencine.cameracontrols.MonitorLutSelection
import com.opencapture.opencine.cameracontrols.importPack
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.runtime.InspectorPreviewFrame
import com.opencapture.opencine.runtime.InspectorPreviewRenderer
import com.opencapture.opencine.runtime.NativeGlBackend
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.BackdropRenderActivity
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.openinstacine.monitor.feed.rememberLiveFeedEffectsPlan
import java.io.File
import java.util.UUID
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED documents/frame, actual app picker/model/Swift packer/live plan and production GLES. */
@RunWith(AndroidJUnit4::class)
class LutDocumentAdoptionNativeTest {
    @Volatile private var plan = FeedEffectsRenderPlan.IDENTITY
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val fileName = "Operator Look.cube"
    private val selectedId = "custom:Operator Look.cube"
    private var pixelSample = 0
    private var renderer: InspectorPreviewRenderer? = null

    @Before fun installTheActualLaunchersBackend() {
        // Monitor library instrumentation has no storefront launcher; install the same real adapter.
        com.opencapture.openinstacine.monitor.MonitorConfiguration.install(
            com.opencapture.openinstacine.monitor.MonitorConfiguration.identity,
            cameraLooks = com.opencapture.openinstacine.monitor.session.LunaCameraLUTProfile.value.cameraLooks,
        ) { context ->
            val wifi = com.opencapture.opencine.platform.CameraWifiCredentialStore(context,
                com.opencapture.openinstacine.monitor.pairing.cameraWifiStorage)
            com.opencapture.opencine.insta360.luna.LunaBackend(context,
                savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove,
                mediaTransfer = com.opencapture.openinstacine.monitor.media.LunaMediaTransferDriver())
        }
    }

    // Bypassing the supplied library loses validation/generation; omitting observation keeps old pixels.
    @Test fun actualDocumentCallbacksPreserveAndRefreshTheStoredLook() {
        assertTrue(SwiftCore.isAvailable, "The actual staged Swift validator must load")
        val base = instrumentation.targetContext.applicationContext
        val domain = "SIMULATED.look7." + (InstrumentationRegistry.getArguments().getString("look7RunId") ?: UUID.randomUUID())
        val root = File(base.filesDir, domain).apply { mkdirs() }
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir() = File(root, "files").apply { mkdirs() }
            override fun getCacheDir() = File(root, "cache").apply { mkdirs() }
            override fun getNoBackupFilesDir() = File(root, "no-backup").apply { mkdirs() }
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                base.getSharedPreferences("$domain.$name", mode)
        }
        // Retain this unique namespace and documents with the owned AVD; never clear existing appdata.
        println("LOOK7 retained fixture root: ${root.absolutePath}")
        context.getSharedPreferences("openpocketcine.operator", Context.MODE_PRIVATE).edit()
            .putBoolean("opc.reliabilityReporting.optIn", false).commit()
        fun document(kind: String, bytes: ByteArray) = File(File(context.cacheDir, kind).apply { mkdirs() }, fileName)
            .apply { writeBytes(bytes) }
        val saved = File(LutCatalog.customDirectory(context.filesDir), fileName)
        val selection = assertNotNull(MonitorLutSelection.of(MonitorLutCategory.CUSTOM, fileName))
        val documents = Documents()
        lateinit var model: AppModel
        var modelCreated = false
        val library = appLutLibrary(context)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    model = AppModel(context)
                    modelCreated = true
                    model.updateLutSelection("creativeWarm")
                    activity.setContent {
                        CompositionLocalProvider(LocalContext provides context,
                            LocalActivityResultRegistryOwner provides documents) {
                            val live = rememberLiveFeedEffectsPlan(model.assist, model.lutSelection,
                                CameraStatus(colorMode = CameraCommands.COLOR_NORMAL), "", null)
                            SideEffect { plan = live }
                            LUTPicker(model, onClose = {})
                        }
                    }
                }
                tap("Custom")
                val red = cube("1 0 0")
                val blue = cube("0 0 1")
                val redDocument = document("valid-red", red)
                val blueDocument = document("valid-blue", blue)
                deliver(documents, redDocument)
                await("actual explicit selection") { model.lutSelection == selectedId }
                assertEquals(1L, library.renderGeneration.value,
                    "The actual document callback must commit through its supplied library")
                assertContentEquals(red, saved.readBytes())
                assertEquals(listOf(255, 0, 0), packedRGB(library, selection))
                await("actual live red payload") { channel(plan, 0) > 230 }
                pixels(context, 255, 0, 0)

                deliver(documents, blueDocument)
                await("same-name generation") { library.renderGeneration.value == 2L }
                await("mounted live plan observes replacement") { channel(plan, 2) > 230 }
                assertEquals(selectedId, model.lutSelection)
                assertEquals(selectedId, OperatorPrefs.lutSelection(context))
                assertEquals(listOf(fileName), library.entries(MonitorLutCategory.CUSTOM).map { it.selection.fileName })
                assertEquals(listOf(0, 0, 255), packedRGB(library, selection))
                pixels(context, 0, 0, 255)

                val rejected = listOf(
                    "malformed" to "not a cube".toByteArray(),
                    "oversized" to ByteArray(MonitorLutLibrary.MAXIMUM_SOURCE_BYTES + 1) { '#'.code.toByte() },
                    "truncated" to ("LUT_3D_SIZE 2\n" + "0 0 1\n".repeat(7)).toByteArray(),
                )
                for ((kind, bytes) in rejected) {
                    // An accepted same-name import clears the preceding error before a new rejection.
                    scenario.onActivity { if (model.assist.lutOn) model.assist.toggle(MonitorAssistTool.LUT) }
                    val beforeAccept = library.renderGeneration.value
                    deliver(documents, blueDocument)
                    await("accepted baseline before $kind") {
                        library.renderGeneration.value == beforeAccept + 1 && model.assist.lutOn
                    }
                    val generation = library.renderGeneration.value
                    scenario.onActivity { if (model.assist.lutOn) model.assist.toggle(MonitorAssistTool.LUT) }
                    deliver(documents, document(kind, bytes))
                    val error = if (kind == "oversized") "The selected document could not be read."
                        else "That document is not a supported .cube LUT."
                    native(error)
                    assertContentEquals(blue, saved.readBytes(), "$kind must preserve the valid original")
                    assertEquals(generation, library.renderGeneration.value, "$kind must not publish a commit")
                    assertEquals(listOf(0, 0, 255), packedRGB(library, selection))
                    assertEquals(selectedId, model.lutSelection)
                    assertEquals(selectedId, OperatorPrefs.lutSelection(context))
                    assertFalse(model.assist.lutOn, "A rejected import must not arm the look")
                    scenario.onActivity { model.assist.armLut() }
                    await("valid look after $kind") { channel(plan, 2) > 230 }
                    pixels(context, 0, 0, 255)
                }

                val beforeDelete = library.renderGeneration.value
                tap("Clear"); tap("Clear LUT")
                await("actual delete and AUTO policy") { !library.contains(selection) && model.lutSelection == "auto" }
                assertNull(library.packedCube(selection))
                assertTrue(library.entries.value.isEmpty())
                await("deleted look leaves the live plan") { plan.lutCube == null }
                assertTrue(model.assist.lutOn)
                assertEquals(beforeDelete + 1, library.renderGeneration.value)
                pixels(context, 80, 80, 80)
                val generationAfterDelete = library.renderGeneration.value
                val brokenPack = File(context.cacheDir, "truncated.zip").apply { writeBytes(byteArrayOf(80, 75, 3, 4, 0)) }
                // Sequential failed archive after actual UI deletion; this does not qualify LOOK-8 races.
                val packResult = runBlocking { library.importPack(MonitorLutCategory.CUSTOM, brokenPack, context.cacheDir) }
                assertEquals(0, packResult.importedCount)
                assertFalse(saved.exists(), "A failed archive must not resurrect an operator-deleted cube")
                assertNull(library.packedCube(selection))
                assertEquals(generationAfterDelete, library.renderGeneration.value)

                for (automatic in listOf("auto", "djiAuto")) {
                    scenario.onActivity {
                        model.updateLutSelection(automatic)
                        if (model.assist.lutOn) model.assist.toggle(MonitorAssistTool.LUT)
                    }
                    val before = library.renderGeneration.value
                    deliver(documents, redDocument)
                    await("AUTO import commits") { library.renderGeneration.value == before + 1 && model.assist.lutOn }
                    assertEquals(automatic, model.lutSelection, "Import preserves explicit AUTO policy")
                    // The stored choice is exact; the existing read API migrates legacy Auto to official Auto.
                    assertEquals(automatic, context.getSharedPreferences("openpocketcine.operator", Context.MODE_PRIVATE)
                        .getString("OpenPocketCine.LUTSelection", null))
                    assertEquals("djiAuto", OperatorPrefs.lutSelection(context))
                    assertTrue(model.assist.lutOn)
                    await("AUTO keeps the actual normal-color plan") { plan.lutCube == null }
                    pixels(context, 80, 80, 80)
                }
                scenario.onActivity { model.assist.toggle(MonitorAssistTool.LUT) }
                val beforeCancel = library.renderGeneration.value
                tap("Import .cube")
                scenario.onActivity { documents.complete(null) }
                instrumentation.waitForIdleSync()
                assertEquals(beforeCancel, library.renderGeneration.value)
                assertEquals("djiAuto", model.lutSelection)
                assertFalse(model.assist.lutOn)
            } catch (error: Throwable) {
                runCatching { captureFailure(context) }.exceptionOrNull()?.let(error::addSuppressed)
                throw error
            } finally {
                scenario.onActivity { it.setContent {}; if (modelCreated) model.close() }
                renderer?.close()
                renderer = null
            }
        }
    }

    private fun captureFailure(context: Context) {
        val directory = File(context.cacheDir, "failure").apply { mkdirs() }
        val automation = instrumentation.uiAutomation
        val info = automation.serviceInfo
        val original = info.flags
        val tree = StringBuilder()
        fun describe(node: AccessibilityNodeInfo, depth: Int = 0) {
            if (depth > 50) return
            val bounds = Rect().also(node::getBoundsInScreen)
            tree.appendLine("${" ".repeat(depth)}${node.packageName} text=${node.text} description=${node.contentDescription} visible=${node.isVisibleToUser} bounds=$bounds")
            for (i in 0 until node.childCount) node.getChild(i)?.let { describe(it, depth + 1) }
        }
        try {
            tree.appendLine("ACTIVE BEFORE DIAGNOSTIC WINDOW FLAGS")
            automation.rootInActiveWindow?.let { describe(it) }
            info.flags = original or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            automation.serviceInfo = info
            if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
            for (window in automation.windows) {
                tree.appendLine("WINDOW ${window.id} active=${window.isActive} focused=${window.isFocused}")
                window.root?.let { describe(it) }
            }
            File(directory, "accessibility.txt").writeText(tree.toString())
            automation.takeScreenshot()?.let { bitmap ->
                try { File(directory, "screen.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
                finally { bitmap.recycle() }
            }
        } finally {
            info.flags = original
            automation.serviceInfo = info
        }
    }

    private fun cube(rgb: String) = ("LUT_3D_SIZE 2\n" + (rgb + "\n").repeat(8)).toByteArray()
    private fun packedRGB(library: MonitorLutLibrary, selection: MonitorLutSelection): List<Int>? =
        library.packedCube(selection)?.rgba?.take(3)?.map { it.toInt() and 255 }
    private fun channel(value: FeedEffectsRenderPlan, channel: Int): Int =
        value.lutCube?.rgba?.get(channel)?.toInt()?.and(255) ?: -1

    private fun pixels(context: Context, red: Int, green: Int, blue: Int) {
        val retained = renderer ?: InspectorPreviewRenderer { NativeGlBackend.create(it) }.also { renderer = it }
        val rgba = ByteArray(4 * 4 * 4) { if (it % 4 == 3) 255.toByte() else 80 }
        val bitmap = retained.render(context, plan, InspectorPreviewFrame(4, 4, rgba))
        try {
            File(context.cacheDir, "gles-${pixelSample++}.png").outputStream().use {
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
            val pixel = bitmap.getPixel(2, 2)
            assertTrue(kotlin.math.abs(Color.red(pixel) - red) < 20, "Actual GLES red: ${Color.red(pixel)}")
            assertTrue(kotlin.math.abs(Color.green(pixel) - green) < 20, "Actual GLES green: ${Color.green(pixel)}")
            assertTrue(kotlin.math.abs(Color.blue(pixel) - blue) < 20, "Actual GLES blue: ${Color.blue(pixel)}")
        } finally {
            bitmap.recycle()
        }
    }

    private fun deliver(documents: Documents, file: File) {
        tap("Import .cube")
        instrumentation.runOnMainSync { documents.complete(Uri.fromFile(file)) }
    }
    private fun await(label: String, ready: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5_000
        do {
            if (ready()) return
            instrumentation.waitForIdleSync(); Thread.yield()
        } while (SystemClock.uptimeMillis() < deadline)
        error("Timed out: $label")
    }
    private fun native(label: String): AccessibilityNodeInfo {
        var result: AccessibilityNodeInfo? = null
        val automation = instrumentation.uiAutomation
        val info = automation.serviceInfo
        val original = info.flags
        try {
            info.flags = original or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            automation.serviceInfo = info
            await("native $label") {
                if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
                for (window in automation.windows) {
                    val root = window.root ?: continue
                    if (root.packageName?.toString() != instrumentation.targetContext.packageName) continue
                    result = find(root, label)
                    if (result != null) break
                }
                result != null
            }
            return assertNotNull(result)
        } finally {
            info.flags = original
            automation.serviceInfo = info
        }
    }
    private fun find(node: AccessibilityNodeInfo, label: String): AccessibilityNodeInfo? {
        if (node.isVisibleToUser && (node.text?.toString() == label || node.contentDescription?.toString() == label)) return node
        for (i in 0 until node.childCount) node.getChild(i)?.let { find(it, label)?.let { return it } }
        return null
    }
    private fun tap(label: String) {
        val bounds = Rect().also(native(label)::getBoundsInScreen)
        val now = SystemClock.uptimeMillis()
        for ((action, time) in listOf(MotionEvent.ACTION_DOWN to now, MotionEvent.ACTION_UP to now + 20)) {
            val event = MotionEvent.obtain(now, time, action, bounds.centerX().toFloat(), bounds.centerY().toFloat(), 0)
            instrumentation.sendPointerSync(event); event.recycle()
        }
        instrumentation.waitForIdleSync()
    }
    /** Only the external document chooser result is replaced; the registered production callback is real. */
    private class Documents : ActivityResultRegistry(), ActivityResultRegistryOwner {
        private var pending: Int? = null
        override val activityResultRegistry: ActivityResultRegistry get() = this
        override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I,
            options: ActivityOptionsCompat?) { pending = requestCode }
        fun complete(uri: Uri?) {
            val code = checkNotNull(pending) { "Actual OpenDocument launcher did not run" }
            pending = null
            dispatchResult(code, if (uri == null) Activity.RESULT_CANCELED else Activity.RESULT_OK,
                uri?.let { Intent().setData(it) })
        }
    }
}
