package com.opencapture.openpocketcine

import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.CrushClipCompensation
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.PeakingColor
import com.opencapture.openpocketcine.assists.WaveformMode
import com.opencapture.openpocketcine.assists.ZebraUnit
import com.opencapture.monitorui.MonitorAudioOrientation
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED values with native input into the app's actual shared tuning menus. */
@RunWith(AndroidJUnit4::class)
class ScopeTuningInputTest {
    @Test fun waveformSelectionBrightnessAndGuideInputReachTheirCurrentBindings() {
        val state = LiveAssistState()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val fixture = mount(scenario, LiveAssistTool.WAVE, state)
            tap(node(fixture) { it.text?.toString() == "Luma" })
            scenario.onActivity { assertEquals(WaveformMode.LUMA, state.waveMode) }
            val slider = node(fixture) { it.rangeInfo != null }
            assertTrue(slider.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.id,
                Bundle().apply { putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, 150f) }))
            settle()
            scenario.onActivity { assertEquals(150, state.waveBrightness) }
            val clipBefore = state.waveGuides.clip
            tap(node(fixture) { it.contentDescription?.toString() == "Safe clip" })
            scenario.onActivity {
                assertEquals(!clipBefore, state.waveGuides.clip)
                assertTrue(state.waveGuides.crush && state.waveGuides.middle)
                assertEquals(100, state.paradeBrightness, "Waveform controls must not edit the parade")
            }
        }
    }

    @Test fun colorAndFractionTargetsKeepNamesHitSizeAndChangedSelectionGuards() {
        var persists = 0
        val state = LiveAssistState(onPersist = { persists++ })
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var fixture = mount(scenario, LiveAssistTool.PEAK, state)
            val red = node(fixture) { it.contentDescription?.toString() == "Red" }
            val bounds = Rect().also(red::getBoundsInScreen)
            var density = 1f
            scenario.onActivity { density = it.resources.displayMetrics.density }
            assertTrue(bounds.width() >= 44 * density - 1 && bounds.height() >= 44 * density - 1)
            tap(red)
            scenario.onActivity { assertEquals(PeakingColor.RED, state.peakingColor) }
            val beforeSameColor = persists
            tap(node(fixture) { it.contentDescription?.toString() == "Red" })
            scenario.onActivity { assertEquals(beforeSameColor, persists) }
            fixture = mount(scenario, LiveAssistTool.HISTO, state)
            val half = node(fixture) { it.contentDescription?.toString() == "0.5" }
            assertEquals("0.5", half.contentDescription.toString(), "Speak the full value, not its fraction glyph")
            tap(half)
            scenario.onActivity { assertEquals(CrushClipCompensation.HALF, state.crushClipCompensation) }
            val beforeSameFraction = persists
            tap(node(fixture) { it.contentDescription?.toString() == "0.5" })
            scenario.onActivity { assertEquals(beforeSameFraction, persists) }
        }
    }

    @Test fun zebraUnitChangesOnlyItsDisplayAxisAndDisabledZoneRejectsInput() {
        val state = LiveAssistState()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val fixture = mount(scenario, LiveAssistTool.ZEBRA, state)
            val original = state.zebraHighlightIRE
            tap(node(fixture) { it.text?.toString() == "0-255" })
            scenario.onActivity {
                assertEquals(ZebraUnit.NATIVE, state.zebraUnit)
                assertEquals(original, state.zebraHighlightIRE, "Changing display units must retain the stored threshold")
            }
            var threshold = node(fixture) { it.contentDescription?.toString() == "Highlight threshold" }
            assertEquals(255f, threshold.rangeInfo.max)
            assertTrue(threshold.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.id,
                Bundle().apply { putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, 255f) }))
            settle()
            scenario.onActivity { assertEquals(100.0, state.zebraHighlightIRE, 0.0001) }
            tap(node(fixture) { it.text?.toString() == "IRE" })
            scenario.onActivity { assertEquals(ZebraUnit.IRE, state.zebraUnit) }
            threshold = node(fixture) { it.contentDescription?.toString() == "Highlight threshold" && it.rangeInfo?.max == 100f }
            assertEquals(100f, threshold.rangeInfo.max)
            tap(node(fixture) { it.contentDescription?.toString() == "Highlight" })
            scenario.onActivity { assertTrue(!state.zebraHighlight) }
            threshold = node(fixture) { it.contentDescription?.toString() == "Highlight threshold" }
            threshold.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.id,
                Bundle().apply { putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, 10f) })
            settle()
            scenario.onActivity {
                assertEquals(100.0, state.zebraHighlightIRE, "Disabled input must retain its last threshold")
                assertTrue(state.zebraMidtone, "Highlight controls must not disable the independent midtone zone")
            }
        }
    }

    @Test fun audioOrientationAndDBSwitchReachTheirExistingStateAndPersistCallbacks() {
        var persists = 0
        val state = LiveAssistState(onPersist = { persists++ })
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val fixture = mount(scenario, LiveAssistTool.AUDIO, state)
            tap(node(fixture) { it.text?.toString() == "Horizontal" })
            scenario.onActivity { assertEquals(MonitorAudioOrientation.HORIZONTAL, state.audioOrientation) }
            val beforeDB = persists
            tap(node(fixture) { it.contentDescription?.toString() == "Show dB values" })
            scenario.onActivity { assertTrue(state.audioShowDB); assertTrue(persists > beforeDB) }
        }
    }

    private fun mount(scenario: ActivityScenario<BackdropRenderActivity>, tool: LiveAssistTool,
        state: LiveAssistState): String {
        val identity = "scope-tuning-${UUID.randomUUID()}"
        scenario.onActivity { activity ->
            activity.setContent {
                Box(Modifier.fillMaxSize().testTag(identity).semantics { testTagsAsResourceId = true }) {
                    AssistOptionsPopup(tool, state, {}, embedded = true)
                }
            }
        }
        settle()
        return identity
    }

    private fun node(identity: String, matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
        fun find(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
            if (predicate(root)) return root
            for (index in 0 until root.childCount) {
                root.getChild(index)?.let { find(it, predicate)?.let { found -> return found } }
            }
            return null
        }
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            val root = InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow
            val fixture = root?.let { find(it) { candidate -> candidate.viewIdResourceName == identity } }
            fixture?.let { find(it, matches)?.let { found -> return found } }
            SystemClock.sleep(60)
        }
        error("No current tuning node in $identity")
    }

    private fun tap(node: AccessibilityNodeInfo) {
        val bounds = Rect().also(node::getBoundsInScreen)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
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
