package com.opencapture.openinstacine.monitor

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingCancellable
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.openinstacine.monitor.diagnostics.AppDiagnostics
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED: the actual session facade and upload gate, without camera/network IO. */
@RunWith(AndroidJUnit4::class)
class CameraReportingSessionTest {
    private class Pending(override val independentOfAutomaticConsent: Boolean) : ReliabilityReportingCancellable {
        var cancellations = 0
        override fun cancel() { cancellations += 1 }
    }

    @Before fun prepare() {
        AppDiagnostics.consent.setOptedIn(true)
        AppDiagnostics.gate.resetForTests()
    }
    @After fun reset() {
        AppDiagnostics.gate.resetForTests()
        AppDiagnostics.consent.resetForTests()
    }

    @Test fun joiningCancelsBothReportKindsAndFailureKeepsTheHoldUntilRetirement() {
        val backend = FakeShellBackend().also { it.phase.value = ConnectionPhase.IDLE }
        val session = liveSession(backend)
        try {
            val automatic = Pending(false)
            val manual = Pending(true)
            AppDiagnostics.gate.register(automatic)
            AppDiagnostics.gate.register(manual)
            assertEquals(0, automatic.cancellations)
            backend.phase.value = ConnectionPhase.JOINING_WIFI
            assertTrue(waitUntil { AppDiagnostics.gate.isCameraSessionActive })
            assertEquals(1, automatic.cancellations)
            assertEquals(1, manual.cancellations)
            // A drop into FAILED and recovery keeps the hold until the session retires (A6-08).
            backend.phase.value = ConnectionPhase.FAILED
            onMain { }
            assertTrue(AppDiagnostics.gate.isCameraSessionActive)
            AppDiagnostics.gate.setCameraIPv4PathReadyForTests(true)
            onMain { session.disconnect() }
            assertFalse(AppDiagnostics.gate.isCameraSessionActive)
            assertTrue(AppDiagnostics.gate.shouldBlockUpload)
            AppDiagnostics.gate.setCameraIPv4PathReadyForTests(false)
            assertFalse(AppDiagnostics.gate.shouldBlockUpload)
        } finally { onMain { session.close() } }
    }

    @Test fun retiringAnOldFacadeCannotReopenReportsDuringItsSuccessor() {
        val first = liveSession(FakeShellBackend())
        val secondBackend = FakeShellBackend().also { it.phase.value = ConnectionPhase.JOINING_WIFI }
        val second = liveSession(secondBackend)
        try {
            assertTrue(waitUntil { AppDiagnostics.gate.isCameraSessionActive })
            onMain { first.close() }
            assertTrue(AppDiagnostics.gate.isCameraSessionActive)
            val late = Pending(true)
            AppDiagnostics.gate.register(late)
            assertEquals(1, late.cancellations)
            onMain { second.close() }
            assertFalse(AppDiagnostics.gate.isCameraSessionActive)
        } finally { onMain { first.close(); second.close() } }
    }
}
