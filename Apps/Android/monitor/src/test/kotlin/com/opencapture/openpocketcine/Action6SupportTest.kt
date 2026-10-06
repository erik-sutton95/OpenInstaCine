package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.headerLabel
import com.opencapture.opencine.cameracontrols.subtitle
import com.opencapture.opencine.vocabulary.ApertureStrategy
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/** Osmo Action 6 parity with the core (handbook `devices/action-6/`). */
class Action6SupportTest {
    private val action6 = "Osmo Action 6"

    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

    @Test fun focusModeSupportFollowsTheModel() {
        assertFalse(CaptureLists.supportsFocusModeOrDefault(CameraModel(action6, supportsFocusMode = false, supportsTapFocus = false)))
    }

    @Test fun captureBytes() {
        assertEquals(CameraCommands.SHOOT_PHOTO, CameraCommands.photoModeRaw(action6))
        assertEquals(
            CaptureShutterPolicy.CaptureKind.SHUTTER_TRIGGER,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_TIMELAPSE, action6),
        )
        assertEquals(
            CaptureShutterPolicy.CaptureKind.VIDEO_RECORD,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_TIMELAPSE, "Osmo Pocket 4"),
        )
    }

    @Test fun apertureChoicesFallBackByModeUntilTheCapabilityLands() {
        val superNight = CameraStatus(shootingMode = CameraCommands.SHOOT_SUPER_NIGHT)
        assertEquals(listOf(0, 2, 3), ApertureStrategy.choices(superNight))
        assertEquals(listOf(1, 2, 3), ApertureStrategy.choices(CameraStatus(expoMode = CameraCommands.EXPO_MANUAL)))
        assertEquals(listOf(4, 2, 3), ApertureStrategy.choices(CameraStatus(expoMode = CameraCommands.EXPO_AUTO)))
        assertEquals(listOf(1), ApertureStrategy.choices(superNight.copy(availableApertureStrategies = listOf(1))))
        assertEquals(listOf("Auto", "f/2.8", "Starburst f/4"), CaptureLists.apertureLabels(CameraStatus()))
        assertEquals(ApertureStrategy.STARBURST, CaptureLists.apertureFromLabel("Starburst f/4"))
        assertEquals("APERTURE", LiveSheet.APERTURE.headerLabel)
        assertEquals("Aperture strategy", LiveSheet.APERTURE.subtitle)
    }
}
