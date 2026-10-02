package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NativeProgramZoomTest {
    @Test fun programmedDemandTracksLinearFactorThroughoutTheLeg() {
        for ((from, to) in listOf(3.0 to 6.0, 6.0 to 3.0)) {
            for (fraction in listOf(0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0)) {
                val demand = NativeProgramZoom.demand(from, to, 2.5, fraction * 2.5)
                assertEquals(NativeProgramZoomCommand.Track(from + (to - from) * fraction), demand.command)
                assertContentEquals(CameraCommands.zoomLens(CamFov.lensPosition(from + (to - from) * fraction)),
                    demand.command.payload, "The target must track factor linearly for the entire leg")
            }
        }
    }

    @Test fun preparationAndTrackingUseTheSameLensPayload() {
        assertContentEquals(NativeProgramZoomCommand.Position(3.0).payload, NativeProgramZoomCommand.Track(3.0).payload)
        assertContentEquals(CameraCommands.zoomStop(), NativeProgramZoomCommand.Stop.payload)
    }

    @Test fun invalidDemandCannotEmitALensTarget() {
        for (values in listOf(listOf(Double.NaN, 3.0, 1.0, 0.0), listOf(1.0, Double.POSITIVE_INFINITY, 1.0, 0.0),
                listOf(1.0, 3.0, 0.0, 0.0), listOf(1.0, 3.0, Double.NaN, 0.0), listOf(1.0, 3.0, 1.0, Double.NaN))) {
            assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(values[0], values[1], values[2], values[3]).command)
        }
    }

    @Test fun nativePathRetainsBAndReplansFromMeasuredZoomAfterResume() {
        val a = GimbalWaypoint(0.0, 0.0, 3.0, 175.0)
        val path = GimbalZoomPath(GimbalProgram(a, a.copy(zoom = 6.0), a.copy(zoom = 4.0), 2.5, 2.0))
        for ((time, zoom) in listOf(0.0 to 3.0, 1.25 to 4.5, 2.5 to 6.0, 3.5 to 5.0, 4.5 to 4.0, 5.0 to 4.0)) {
            assertEquals(NativeProgramZoomCommand.Track(zoom), path.nativeDemand(time).command)
        }
        val resumed = path.remaining(1.5, 5.2, quantized = true)
        assertEquals(NativeProgramZoomCommand.Track(5.2), resumed.nativeDemand(0.0).command)
        assertEquals(NativeProgramZoomCommand.Track(5.6), resumed.nativeDemand(0.5).command)
        assertEquals(NativeProgramZoomCommand.Track(6.0), resumed.nativeDemand(1.0).command)
    }

    @Test fun crossingAnEpsilonBeforeBPreservesTheNextLegStart() {
        val a = GimbalWaypoint(0.0, 0.0, 3.0, 175.0)
        val path = GimbalZoomPath(GimbalProgram(a, a.copy(zoom = 6.0), a, 2.5, 2.5))
        assertEquals(path.nativeDemand(2.5), path.nativeDemand(2.5 - 5e-10))
        assertEquals(NativeProgramZoomCommand.Track(6.0), path.nativeDemand(2.5).command)
    }

    @Test fun lateEndpointRemainsUntilATrackingSampleIsAdmitted() {
        val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true), a))
        repeat(294) { engine.tick(0.01, a) }
        assertTrue((engine.nativeZoomDemand!!.command as NativeProgramZoomCommand.Track).factor < 3.0)
        engine.tick(0.065, a)
        assertEquals("B→A", engine.readout(a)!!.label)
        assertEquals(NativeProgramZoomCommand.Track(3.0), engine.nativeZoomDemand!!.command)
        engine.tick(0.01, a)
        assertEquals(NativeProgramZoomCommand.Track(3.0), engine.consumeNativeZoomDemand()!!.command)
        assertTrue((engine.nativeZoomDemand!!.command as NativeProgramZoomCommand.Track).factor < 3.0)
        assertTrue(engine.pause(a))
        assertNull(engine.nativeZoomDemand)
        engine.cancel()
        assertNull(engine.nativeZoomDemand)
    }

}
