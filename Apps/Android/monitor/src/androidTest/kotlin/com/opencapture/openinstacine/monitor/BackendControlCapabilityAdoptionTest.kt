package com.opencapture.openinstacine.monitor

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.core.SupportStatus
import com.opencapture.opencine.insta360.shell.CameraCapability
import com.opencapture.opencine.insta360.shell.CameraIdentity
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED backend facts through the real shell facade; no camera or network commands. */
@RunWith(AndroidJUnit4::class)
class BackendControlCapabilityAdoptionTest {
    @Test fun backendInputsRestrictConnectedControlsWithoutChangingPreConnectionProfile() {
        var declarations = emptySet<CameraCapability>()
        val backend = object : FakeShellBackend() {
            override val capabilities get() = declarations
        }.apply { connected.value = null; phase.value = ConnectionPhase.IDLE }
        val facade = liveSession(backend)
        try {
            onMain {
                val sheet = instaCaptureSessionState({ facade.aeLock.value }, { facade.awbLockKelvin.value },
                    { false }, { facade.isFormatPinActive }, controls = facade::controlCapabilities)
                assertTrue(facade.controlCapabilities().focus.isOffered)
                assertTrue(sheet.focusModeSupported)
                assertNotNull(facade.nativeMeteringSource(false) { true })
                backend.connected.value = CameraIdentity("SIMULATED-CAPABILITY", "SIMULATED", "Luna Ultra")
                backend.phase.value = ConnectionPhase.LIVE
                assertEquals(SupportStatus.UNSUPPORTED, facade.controlCapabilities().focus.support)
                assertFalse(facade.supportsFocusMode || facade.supportsTapFocus)
                assertEquals(facade.controlCapabilities(), sheet.controlCapabilities)
                assertFalse(sheet.focusModeSupported)
                assertNull(facade.nativeMeteringSource(false) { true }, "an unsupported camera control has no native UI slot")
                declarations = setOf(CameraCapability.CAMERA_SETTINGS, CameraCapability.FOCUS,
                    CameraCapability.ZOOM, CameraCapability.GIMBAL)
                assertTrue(facade.controlCapabilities().focus.isOffered
                    && facade.controlCapabilities().zoom.isOffered && facade.controlCapabilities().gimbal.isOffered)
                assertTrue(facade.supportsFocusMode && facade.supportsTapFocus)
                assertTrue(sheet.focusModeSupported)
                assertNotNull(facade.nativeMeteringSource(false) { true })
                backend.connected.value = null
                backend.phase.value = ConnectionPhase.IDLE
                assertTrue(facade.controlCapabilities().focus.isOffered
                    && facade.controlCapabilities().zoom.isOffered && facade.controlCapabilities().gimbal.isOffered)
                assertEquals(facade.controlCapabilities(), sheet.controlCapabilities)
            }
        } finally { onMain { facade.close() } }
    }
}
