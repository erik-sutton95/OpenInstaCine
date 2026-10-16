package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.core.CapabilitySnapshot
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.insta360.luna.LunaCameraSession
import com.opencapture.opencine.vocabulary.ControlCapabilities
import com.opencapture.opencine.vocabulary.controls
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The capture sheet host values, as on main. */
class CaptureSheetHostTest {
    @Test fun onlyIsoShutterAndWhiteBalanceOpenThroughCore() {
        assertEquals(SettingKey.ISO, captureSettingKey(LiveSheet.ISO))
        assertEquals(SettingKey.SHUTTER, captureSettingKey(LiveSheet.SHUTTER))
        assertEquals(SettingKey.WHITE_BALANCE, captureSettingKey(LiveSheet.WB))
        for (sheet in LiveSheet.entries - setOf(LiveSheet.ISO, LiveSheet.SHUTTER, LiveSheet.WB)) {
            assertNull(captureSettingKey(sheet), "$sheet (EV and focus included) stays on the typed path")
        }
    }

    @Test fun locksFollowTheSessionAndTheFormatPinIsReadLive() {
        var aeLock: Any? = null
        var awbKelvin: Int? = null
        var pinned = true
        val state = instaCaptureSessionState({ aeLock }, { awbKelvin }, { false }, { pinned }, { true }, { false })
        assertFalse(state.aeLocked)
        assertNull(state.awbLockKelvin)
        assertFalse(state.awbLockOffered)
        assertTrue(state.formatPinned)
        aeLock = Any()
        awbKelvin = 5600
        pinned = false
        assertTrue(state.aeLocked)
        assertEquals(5600, state.awbLockKelvin)
        assertFalse(state.formatPinned)
    }

    @Test fun declaredApertureRowsDrawWhileFocusAndNativeIsoHopFollowTheSession() {
        var focus = false
        var hop = false
        val state = instaCaptureSessionState({ null }, { null }, { false }, { false }, { focus }, { hop }, irisSupported = { true })
        assertTrue(state.irisSupported)
        assertFalse(instaCaptureSessionState({ null }, { null }, { false }, { false }, { false }, { false }).irisSupported)
        assertFalse(state.focusModeSupported)
        assertFalse(state.nativeIsoHopSupported, "No native ISO hop toggle without the session capability")
        focus = true
        hop = true
        assertTrue(state.focusModeSupported)
        assertTrue(state.nativeIsoHopSupported)
    }

    /** A connected Luna session's model replaces the flags; before connection the flags stay. */
    @Test fun theConnectedLunaModelDecidesTheCaptureGates() {
        var connected: ControlCapabilities? = null
        val state = instaCaptureSessionState({ null }, { null }, { false }, { false }, { false }, { false },
            controls = { connected })
        assertFalse(state.controls().focus.isOffered, "before connection: the flags")
        connected = ControlCapabilities.derive(CapabilitySnapshot(), LunaCameraSession.CAPTURE_PROFILE, LunaCameraSession.MOTION)
        val controls = state.controls()
        assertTrue(controls.focus.isOffered)
        assertFalse(controls.iris.isOffered)
        assertFalse(controls.audio.isOffered)
        assertTrue(controls.faceMetering.isOffered)
        assertTrue(controls.zoom.isOffered && controls.gimbal.isOffered)
        assertEquals(false, controls.nativeISO.hop)
        assertEquals(false, controls.nativeISO.ceiling)
    }
}
