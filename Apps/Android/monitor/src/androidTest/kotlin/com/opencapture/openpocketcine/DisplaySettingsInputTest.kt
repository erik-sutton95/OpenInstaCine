package com.opencapture.openpocketcine

import android.content.Context
import android.graphics.Rect
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.cameracontrols.OperatorDisplayRows
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED offline admission; the actual Display body writes the actual app model and store. */
@RunWith(AndroidJUnit4::class)
class DisplaySettingsInputTest {
    @Before fun installInstaBackend() {
        // Library instrumentation runs in its own package, without the brand launcher.
        // Use the launcher's actual backend composition; this fixture never starts discovery.
        MonitorConfiguration.install(MonitorConfiguration.identity) { context ->
            val wifi = com.opencapture.openpocketcine.pairing.CameraWifiCredentialStore(context)
            com.opencapture.opencine.insta360.luna.LunaBackend(context,
                savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove)
        }
    }
    @Test fun actualDisplayKeepsLayoutsAndPinsAfterRecreatingTheAppModel() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("openpocketcine.operator", Context.MODE_PRIVATE)
        val keys = listOf("OpenPocketCine.DispChrome.Live", "OpenPocketCine.DispChrome.Clean",
            "OpenPocketCine.CleanViewPins.v1")
        val previous = prefs.all.filterKeys { it in keys }
        try {
            OperatorPrefs.setDispLive(context, PocketDispChrome.liveDefaults)
            OperatorPrefs.setDispClean(context, PocketDispChrome.cleanDefaults)
            OperatorPrefs.setCleanViewPinnedTools(context, OperatorPrefs.DEFAULT_CLEAN_PINS)
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                var model: AppModel? = null
                fun mount() {
                    scenario.onActivity { activity ->
                        val fresh = AppModel(activity)
                        model = fresh
                        // Each recreated model gets a fresh fixture viewport; saved app values remain real.
                        val scroll = ScrollState(0)
                        activity.setContent {
                            Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(12.dp)
                                .semantics { testTagsAsResourceId = true }) {
                                OperatorDisplayRows(fresh, fresh.operatorSetupState(), operatorSetupApp(fresh), isLive = false)
                            }
                        }
                    }
                    settle()
                }
                try {
                    mount()
                    assertFalse(hasNode("monitor.settings.display.edit.LIVE"), "Offline cannot enter the live editor")
                    tap(visibleNode("monitor.settings.display.toggle.LIVE.STATUS_BAR"))
                    assertFalse(OperatorPrefs.dispLive(context).statusBar)
                    assertFalse(OperatorPrefs.dispClean(context).statusBar, "Live must preserve Clean")
                    tap(visibleNode("monitor.settings.display.toggle.CLEAN.STATUS_BAR"))
                    assertTrue(OperatorPrefs.dispClean(context).statusBar)
                    assertFalse(OperatorPrefs.dispLive(context).statusBar)
                    val pin = visibleNode("monitor.settings.display.toggle.clean.pin.ZEBRA")
                    assertEquals("Off", pin.stateDescription.toString(), "Seeded pin starts disabled")
                    tap(pin)
                    assertTrue("ZEBRA" in OperatorPrefs.cleanViewPinnedTools(context))
                    scenario.onActivity { model?.close(); model = null }
                    scenario.recreate()
                    mount()
                    assertEquals("Off", visibleNode("monitor.settings.display.toggle.LIVE.STATUS_BAR").stateDescription.toString())
                    assertEquals("On", visibleNode("monitor.settings.display.toggle.CLEAN.STATUS_BAR").stateDescription.toString())
                    assertEquals("On", visibleNode("monitor.settings.display.toggle.clean.pin.ZEBRA").stateDescription.toString())
                    assertTrue(OperatorPrefs.DEFAULT_CLEAN_PINS.all { it in OperatorPrefs.cleanViewPinnedTools(context) })
                } finally { scenario.onActivity { model?.close() } }
            }
        } finally {
            val editor = prefs.edit()
            keys.forEach(editor::remove)
            previous.forEach { (key, value) ->
                when (value) {
                    is String -> editor.putString(key, value)
                    is Set<*> -> editor.putStringSet(key, value.filterIsInstance<String>().toSet())
                    else -> error("Unexpected display preference type for $key")
                }
            }
            assertTrue(editor.commit(), "Restore exact saved bytes, sets and absent keys")
        }
    }

    private fun find(root: AccessibilityNodeInfo, matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (matches(root)) return root
        for (index in 0 until root.childCount) root.getChild(index)?.let { child ->
            find(child, matches)?.let { return it }
        }
        return null
    }

    private fun hasNode(tag: String): Boolean =
        InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let {
            find(it) { node -> node.viewIdResourceName == tag }
        } != null

    private fun visibleNode(tag: String): AccessibilityNodeInfo {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        repeat(24) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root == null || root.packageName?.toString() != instrumentation.targetContext.packageName) {
                settle()
                return@repeat
            }
            val node = find(root) { it.viewIdResourceName == tag }
            if (node != null) {
                val bounds = Rect().also(node::getBoundsInScreen)
                val window = Rect().also(root::getBoundsInScreen)
                val cellHeight = if (tag.contains(".pin.")) 46 else 22
                val minimumHeight = cellHeight * instrumentation.targetContext.resources.displayMetrics.density
                if (bounds.width() > 0 && bounds.height() >= minimumHeight - 2 && window.contains(bounds)) {
                    SystemClock.sleep(250)
                    val current = instrumentation.uiAutomation.rootInActiveWindow?.let { fresh ->
                        find(fresh) { it.viewIdResourceName == tag }
                    }
                    val currentBounds = current?.let { Rect().also(it::getBoundsInScreen) }
                    if (current != null && currentBounds == bounds) return current
                    return@repeat
                }
            }
            val scroll = checkNotNull(find(root) { it.isScrollable })
            val viewport = Rect().also(scroll::getBoundsInScreen)
            val down = SystemClock.uptimeMillis()
            // Move a fraction of the viewport so a partially visible control cannot be skipped.
            for (step in 0..8) {
                val action = if (step == 0) MotionEvent.ACTION_DOWN else MotionEvent.ACTION_MOVE
                val y = viewport.top + viewport.height() * (0.78f - 0.25f * step / 8f)
                val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                    viewport.exactCenterX(), y, 0)
                assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true))
                event.recycle()
                SystemClock.sleep(20)
            }
            // A held release ends scrolling without a fling moving the next hit target.
            SystemClock.sleep(250)
            val up = MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP,
                viewport.exactCenterX(), viewport.top + viewport.height() * 0.53f, 0)
            assertTrue(instrumentation.uiAutomation.injectInputEvent(up, true))
            up.recycle()
            settle()
        }
        error("Actual Display control is not reachable: $tag")
    }

    private fun tap(node: AccessibilityNodeInfo) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bounds = Rect().also(node::getBoundsInScreen)
        val down = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                bounds.exactCenterX(), bounds.exactCenterY(), 0)
            assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true))
            event.recycle()
        }
        settle()
    }

    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(180)
    }
}
