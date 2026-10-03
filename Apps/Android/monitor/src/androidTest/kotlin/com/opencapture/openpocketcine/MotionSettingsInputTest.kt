package com.opencapture.openpocketcine

import android.content.Context
import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorJoystickSize
import com.opencapture.monitorui.settings.MonitorJoystickSettings
import com.opencapture.monitorui.settings.MonitorMotionChoiceSetting
import com.opencapture.monitorui.settings.MonitorMotionIntegerSetting
import com.opencapture.monitorui.settings.MonitorMotionToggleSetting
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED camera eligibility; native shared controls write the app's existing preference store. */
@RunWith(AndroidJUnit4::class)
class MotionSettingsInputTest {
    @Test fun nativeJoystickInputSurvivesRecreatingItsBindings() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("openpocketcine.operator", Context.MODE_PRIVATE)
        val keys = listOf("VirtualJoystickInvertPan", "VirtualJoystickInvertTilt",
            "VirtualJoystickDeadzonePercent", "VirtualJoystickResponseCurve", "VirtualJoystickSize")
            .map { "OpenPocketCine.$it" }
        val previous = prefs.all.filterKeys { it in keys }
        try {
            OperatorPrefs.setVirtualJoystickInvertPan(context, false)
            OperatorPrefs.setVirtualJoystickInvertTilt(context, false)
            OperatorPrefs.setVirtualJoystickDeadzonePercent(context, 8)
            OperatorPrefs.setVirtualJoystickResponseCurve(context, CameraCommands.VirtualJoystickCurve.STANDARD)
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                mount(scenario)
                tap(node { it.viewIdResourceName == "gimbal.virtual.invertPan" })
                tap(node { it.text?.toString() == "Fine" || it.contentDescription?.toString() == "Fine" })
                val slider = node { it.rangeInfo != null }
                val range = checkNotNull(slider.rangeInfo)
                assertTrue(slider.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.id,
                    Bundle().apply { putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE,
                        range.min + (range.max - range.min) * .8f) }))
                settle()
                assertTrue(OperatorPrefs.virtualJoystickInvertPan(context))
                assertEquals(20, OperatorPrefs.virtualJoystickDeadzonePercent(context))
                assertEquals(CameraCommands.VirtualJoystickCurve.FINE, OperatorPrefs.virtualJoystickResponseCurve(context))
                // Dispose the native composition before reading the saved values into fresh bindings.
                scenario.onActivity { it.setContent {} }
                settle()
                mount(scenario)
                assertEquals("On", node { it.viewIdResourceName == "gimbal.virtual.invertPan" }.stateDescription.toString())
                tap(node { it.viewIdResourceName == "gimbal.virtual.invertPan" })
                assertEquals(false, OperatorPrefs.virtualJoystickInvertPan(context))
                assertEquals(20, OperatorPrefs.virtualJoystickDeadzonePercent(context))
                assertEquals(false, OperatorPrefs.virtualJoystickInvertTilt(context), "Pan input must preserve tilt")
            }
        } finally {
            val editor = prefs.edit()
            keys.forEach(editor::remove)
            previous.forEach { (key, value) ->
                when (value) {
                    is Boolean -> editor.putBoolean(key, value)
                    is Int -> editor.putInt(key, value)
                    is String -> editor.putString(key, value)
                    else -> error("Unexpected motion preference type for $key")
                }
            }
            assertTrue(editor.commit(), "Restore exact preference values and absent keys")
        }
    }

    private fun mount(scenario: ActivityScenario<BackdropRenderActivity>) {
        scenario.onActivity { activity ->
            activity.setContent {
                var pan by remember { mutableStateOf(OperatorPrefs.virtualJoystickInvertPan(activity)) }
                var tilt by remember { mutableStateOf(OperatorPrefs.virtualJoystickInvertTilt(activity)) }
                var zone by remember { mutableStateOf(OperatorPrefs.virtualJoystickDeadzonePercent(activity)) }
                var curve by remember { mutableStateOf(OperatorPrefs.virtualJoystickResponseCurve(activity)) }
                var size by remember { mutableStateOf(OperatorPrefs.virtualJoystickSize(activity)) }
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)
                    .semantics { testTagsAsResourceId = true }) {
                    MonitorJoystickSettings(
                        size = MonitorMotionChoiceSetting(MonitorJoystickSize.entries.map { it.label }, size.label, "") {
                            size = MonitorJoystickSize.fromLabel(it); OperatorPrefs.setVirtualJoystickSize(activity, size)
                        },
                        invertPan = MonitorMotionToggleSetting(pan, "") {
                            pan = it; OperatorPrefs.setVirtualJoystickInvertPan(activity, it)
                        },
                        invertTilt = MonitorMotionToggleSetting(tilt, "") {
                            tilt = it; OperatorPrefs.setVirtualJoystickInvertTilt(activity, it)
                        },
                        deadZone = MonitorMotionIntegerSetting(zone, 0..25, "", "%") {
                            zone = it; OperatorPrefs.setVirtualJoystickDeadzonePercent(activity, it)
                        },
                        response = MonitorMotionChoiceSetting(CameraCommands.VirtualJoystickCurve.entries.map { it.label },
                            curve.label, "") {
                            curve = CameraCommands.VirtualJoystickCurve.fromLabel(it)
                            OperatorPrefs.setVirtualJoystickResponseCurve(activity, curve)
                        }, identifierPrefix = "gimbal.virtual",
                    )
                }
            }
        }
        settle()
    }

    private fun node(matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
        fun find(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (matches(root)) return root
            for (index in 0 until root.childCount) root.getChild(index)?.let { find(it)?.let { found -> return found } }
            return null
        }
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let {
                find(it)?.let { found -> return found }
            }
            SystemClock.sleep(60)
        }
        error("No current motion setting node")
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
