package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.captureQuickFocusControl
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.GamepadGimbalStick
import com.opencapture.opencine.vocabulary.GimbalDoubleTap
import com.opencapture.opencine.vocabulary.GimbalMode
import com.opencapture.opencine.vocabulary.GimbalRamp
import com.opencapture.opencine.vocabulary.GimbalSpeed
import com.opencapture.opencine.vocabulary.IsoLimit
import com.opencapture.openpocketcine.session.LunaShellMapping
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Every picker the app builds from camera-vocabulary values, pinned to the lists main showed while the
 * app still carried its own copy of the vocabulary (I-2). The Luna session's names and color wheel come
 * from its label profile.
 */
class PickerListsTest {
    private val luna = LunaShellMapping.profile
    private fun list(text: String) = text.split("|")

    @Test fun gimbalPickers() {
        assertEquals(list("Roll Lock|Roll & Tilt|FPV|FPV-V"), GimbalMode.pickerOrder.map { it.label(luna.labels) })
        assertEquals(list("Follow|Tilt locked|FPV|Direction Lock"), GimbalMode.pickerOrder.map { it.label })
        assertEquals(list("Slow|Default|Fast"), GimbalSpeed.pickerOrder.map { it.label })
        assertEquals(list("Off|Soft|Medium"), GimbalRamp.pickerOrder.map { it.label })
        assertEquals(list("Recenter|Level"), GimbalDoubleTap.pickerOrder.map { it.label })
    }

    @Test fun focusPicker() {
        assertEquals(list("AF-S|AF-C|Showcase"), captureQuickFocusControl(CameraStatus(), luna.labels.focusLabels).options)
        assertEquals(list("AF-S|AF-C|Showcase|Lock|Priority"), captureQuickFocusControl(CameraStatus()).options)
    }

    @Test fun shootingModePicker() {
        assertEquals(
            list("Video|Photo|Timelapse|TimeShift|PureVideo|Slow Motion"),
            CaptureLists.shootingModeLabels("Insta360 Luna Ultra", -1, luna.labels),
        )
    }

    @Test fun colorPicker() {
        val status = CameraStatus(availableColorModes = LunaShellMapping.colorModes)
        assertEquals(
            list("Standard|I-Log|Dolby Vision"),
            CaptureLists.colorWheelLabels(status, "generic", "Insta360 Luna Ultra", luna.labels),
        )
    }

    @Test fun isoPicker() {
        for (color in listOf(CameraCommands.COLOR_ILOG, CameraCommands.COLOR_NORMAL)) {
            val status = CameraStatus(colorMode = color, availableIsoIndices = LunaShellMapping.isoIndices)
            assertEquals(list("100|160|200|400|800|1600|3200|6400"), CaptureLists.isoDrumLabels(status), "color $color")
        }
    }

    @Test fun exposureAndControlPickers() {
        assertEquals(list("Auto|Manual"), CaptureLists.expoLabels)
        assertEquals(
            list("−3.0|−2.7|−2.3|−2.0|−1.7|−1.3|−1.0|−0.7|−0.3|0.0|+0.3|+0.7|+1.0|+1.3|+1.7|+2.0|+2.3|+2.7|+3.0"),
            CaptureLists.evLabels,
        )
        assertEquals(list("Max200|Max400|Max800|Max1600|Max3200|Max6400|Max12800|Max25600"), IsoLimit.entries.map { it.name })
        assertEquals(list("Linear|Standard|Fine"), CameraCommands.VirtualJoystickCurve.entries.map { it.label })
        assertEquals(list("Left|Right"), GamepadGimbalStick.entries.map { it.label })
    }
}
