package com.opencapture.openpocketcine

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.graphics.Rect
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.monitorui.settings.MonitorViewAssistSettings
import com.opencapture.openpocketcine.assists.*
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED source; actual card actions and the actual app preference factory are exercised. */
@RunWith(AndroidJUnit4::class)
class AssistSettingsCompositionInputTest {
    @Test fun actualEightCardResetsReloadAndOffZebraStillAcceptsConfiguration() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val base = instrumentation.targetContext.applicationContext
        val domain = "assist-settings-test." + UUID.randomUUID()
        val domains = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val key = "$domain.$name"
                domains += key
                return base.getSharedPreferences(key, mode)
            }
        }
        try {
            val state = createLiveAssistState(context)
            state.setFalseColor(scale = FalseColorScale.IRE, reference = false)
            state.setWaveform(mode = WaveformMode.LUMA, brightness = 173,
                guides = state.waveGuides.copy(clip = false, crush = false, middle = false))
            state.setParade(mode = ParadeMode.YRGB, brightness = 177,
                guides = state.paradeGuides.copy(clip = false, crush = false, middle = false))
            state.setHistogram(traffic = false)
            state.setCompensation(CrushClipCompensation.entries.last())
            state.setVectorscope(zoom = VectorscopeZoom.X4, brightness = 181)
            state.setPeaking(color = PeakingColor.GREEN, sense = PeakingSense.entries.first())
            state.setZebraHighlight(enabled = false, ire = 42.0, color = ZebraPaint.WHITE)
            state.setZebraMidtone(enabled = false, ire = 37.0, color = ZebraPaint.CYAN)
            OperatorPrefs.setCleanViewPinnedTools(context, setOf("WAVE"))
            OperatorPrefs.setPlaybackVisibleAssistTools(context, setOf("FALSE"))
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                fun mount(tool: MonitorAssistTool) {
                    scenario.onActivity { activity ->
                        activity.setContent {
                            Column(Modifier.fillMaxSize().padding(12.dp)
                                .semantics { testTagsAsResourceId = true }) {
                                MonitorViewAssistSettings(assistSettingsSections(state, 0).filter { it.tool == tool })
                            }
                        }
                    }
                    settle()
                    nativeControl("Reset to defaults")
                }
                mount(MonitorAssistTool.ZEBRA)
                val red = nativeControl("Red")
                assertTrue(red.isEnabled, "The actual donor allows editing an off zone")
                tap(red)
                instrumentation.waitForIdleSync()
                assertFalse(state.zebraHighlight)
                assertEquals(ZebraPaint.RED, createLiveAssistState(context).zebraHighlightColor)
                for (tool in listOf(MonitorAssistTool.FALSE, MonitorAssistTool.ZEBRA,
                    MonitorAssistTool.WAVE, MonitorAssistTool.PARADE, MonitorAssistTool.HISTO,
                    MonitorAssistTool.VECTOR, MonitorAssistTool.PEAK, MonitorAssistTool.LIGHTS)) {
                    mount(tool)
                    val reset = nativeControl("Reset to defaults")
                    tap(reset)
                    instrumentation.waitForIdleSync()
                    val saved = createLiveAssistState(context)
                    when (tool) {
                        MonitorAssistTool.FALSE -> {
                            assertEquals(FalseColorScale.SCENE_STOPS, saved.falseColorScale)
                            assertTrue(saved.falseColorReference)
                        }
                        MonitorAssistTool.ZEBRA -> {
                            assertEquals(ZebraUnit.IRE, saved.zebraUnit)
                            assertTrue(saved.zebraHighlight && saved.zebraMidtone)
                            assertEquals(LiveZebra.HIGHLIGHT_IRE, saved.zebraHighlightIRE)
                            assertEquals(LiveZebra.MIDTONE_IRE, saved.zebraMidtoneIRE)
                            assertEquals(ZebraPaint.WHITE, saved.zebraHighlightColor)
                            assertEquals(ZebraPaint.AMBER, saved.zebraMidtoneColor)
                        }
                        MonitorAssistTool.WAVE -> {
                            assertEquals(WaveformMode.RGB, saved.waveMode)
                            assertEquals(100, saved.waveBrightness)
                            assertEquals(ScopeGuides(), saved.waveGuides)
                        }
                        MonitorAssistTool.PARADE -> {
                            assertEquals(ParadeMode.RGB, saved.paradeMode)
                            assertEquals(100, saved.paradeBrightness)
                            assertEquals(ScopeGuides(), saved.paradeGuides)
                        }
                        MonitorAssistTool.HISTO -> {
                            assertTrue(saved.histoTrafficLights)
                            assertEquals(CrushClipCompensation.ZERO, saved.crushClipCompensation)
                            state.setCompensation(CrushClipCompensation.entries.last())
                        }
                        MonitorAssistTool.VECTOR -> {
                            assertEquals(VectorscopeZoom.X1, saved.vectorZoom)
                            assertEquals(100, saved.vectorBrightness)
                        }
                        MonitorAssistTool.PEAK -> {
                            assertEquals(PeakingColor.RED, saved.peakingColor)
                            assertEquals(PeakingSense.MED, saved.peakingSensitivity)
                        }
                        MonitorAssistTool.LIGHTS -> {
                            assertEquals(CrushClipCompensation.ZERO, saved.crushClipCompensation)
                            assertTrue(saved.histoTrafficLights, "Shared compensation preserves histogram enablement")
                        }
                        else -> error("Unexpected settings tool")
                    }
                    assertEquals(setOf("WAVE"), OperatorPrefs.cleanViewPinnedTools(context))
                    assertEquals(setOf("FALSE"), OperatorPrefs.playbackVisibleAssistTools(context))
                }
            }
        } finally {
            domains.forEach { assertTrue(base.deleteSharedPreferences(it)) }
        }
    }

    private fun find(root: AccessibilityNodeInfo, description: String): AccessibilityNodeInfo? {
        if (root.contentDescription?.toString() == description) return root
        for (index in 0 until root.childCount) root.getChild(index)?.let { child ->
            find(child, description)?.let { return it }
        }
        return null
    }

    private fun nativeControl(description: String): AccessibilityNodeInfo {
        settle()
        val root = checkNotNull(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
        val node = checkNotNull(find(root, description)) { "Actual control missing: $description" }
        assertTrue(node.isVisibleToUser)
        val bounds = Rect().also(node::getBoundsInScreen)
        assertTrue(bounds.width() > 0 && bounds.height() > 0)
        return node
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
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.waitForIdle(100, 5_000)
    }

}
