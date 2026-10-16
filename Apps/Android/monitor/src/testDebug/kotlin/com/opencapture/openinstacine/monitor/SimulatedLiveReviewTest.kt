package com.opencapture.openinstacine.monitor

import com.opencapture.monitorui.ReviewLiveValues
import com.opencapture.opencine.insta360.shell.CameraColorProfile
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import kotlin.test.Test
import kotlin.test.assertEquals

/** SIMULATED: the LIVE review stages the shared review values as a connected Luna reports them. */
class SimulatedLiveReviewTest {
    private val values = ReviewLiveValues.SIMULATED

    @Test fun theBackendIsLiveWithTheSharedValuesInTheLunaColour() {
        val backend = SimulatedLiveBackend(values)
        assertEquals(ConnectionPhase.LIVE, backend.phase.value)
        val readout = backend.readout.value
        assertEquals(values.iso, readout.videoExposure?.iso)
        assertEquals(values.whiteBalanceKelvin, readout.whiteBalanceKelvin)
        assertEquals(CameraColorProfile.LOG, readout.color)
        assertEquals(listOf(3840, 2160), listOf(readout.recordFormat?.width, readout.recordFormat?.height))
        assertEquals(25.0, readout.recordFormat?.fps)
    }

    @Test fun theSessionReportsTheRecordingFormatTheHeaderShows() {
        val snapshot = ReviewLiveSession(values).snapshots.value
        assertEquals("I-Log", snapshot.recordingFormat.profile.value)
        assertEquals(3840, snapshot.recordingFormat.dimensions.value?.width)
        assertEquals(2160, snapshot.recordingFormat.dimensions.value?.height)
    }
}
