package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GimbalProgramZoomTest {
    private val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
    private val b = GimbalWaypoint(20.0, 0.0, 3.0, 175.0)
    private val c = GimbalWaypoint(20.0, 20.0, 2.0, 155.0)
    private val program = GimbalProgram(a, b, c, durationAB = 1.0, durationBC = 2.0, loop = true)
    private val pro = CameraModel("Osmo Pocket 4 Pro")
    private val ready = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0)

    @Test fun onlyDifferentSavedZoomAmountsEnableAutomaticZoom() {
        assertFalse(GimbalProgram().changesZoom)
        assertFalse(program.copy(b = b.copy(zoom = 1.0), c = null).changesZoom)
        assertFalse(program.copy(b = b.copy(zoom = 1.0 + 0.5e-6), c = null).changesZoom)
        assertTrue(program.changesZoom)
        assertTrue(program.copy(b = b.copy(zoom = 1.0)).changesZoom)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(program.copy(b = b.copy(zoom = 1.0), c = null), a))
        assertNull(engine.programmedZoomTarget)
    }

    @Test fun zoomVisitsBExactlyWithClippedLookAheadAndResumeUsesMeasuredZoom() {
        val path = GimbalZoomPath(program)
        assertEquals(1.1, path.position(0.0), 1e-9)
        assertEquals(3.0, path.position(0.97), 1e-9)
        assertEquals(2.975, path.position(1.0), 1e-9)
        assertEquals(2.0, path.position(3.0), 1e-9)
        val remaining = path.remaining(1.23, 1.7, quantized = true)
        assertEquals(1.8, remaining.duration, 1e-9)
        assertEquals(1.7 + 0.3 * 0.05 / 1.8, remaining.position(0.0), 1e-9)
        assertEquals(1.77, path.remaining(1.23, 1.7, quantized = false).duration, 1e-9)
        val nearB = path.remaining(0.96, 1.7, quantized = false)
        assertEquals(2.04, nearB.duration, 1e-9)
        assertEquals(0.04, nearB.legs.first().duration, 1e-9)
        assertEquals(3.0, nearB.position(0.0), 1e-9)
    }

    @Test fun engineZoomTracksExactAndSmoothLoopPassesAndRestoresFullPathAfterPause() {
        for (smoothness in listOf(0.0, 1.0)) {
            val saved = program.copy(smoothness = smoothness)
            val engine = GimbalMoveEngine()
            assertTrue(engine.start(saved, a))
            var now = 0.0
            var origin = a
            var target = a
            var motionAt = 0.0
            var motionDuration = 1.0
            fun physical() = GimbalMoveEngine.lerp(origin, target, (now - motionAt) / motionDuration)
            var pass = -1
            var passAt = 0.0
            var expected = GimbalZoomPath(saved)
            var zoomAt = 0.0
            var paused = false
            var resumeCommand = false
            repeat(1_500) {
                now += 0.01
                if (resumeCommand) {
                    zoomAt += 0.01
                    resumeCommand = false
                }
                val live = physical()
                val before = engine.readout(live)!!
                val out = engine.tick(0.01, live)!!
                val after = engine.readout(live)!!
                val turn = (before.label == "B→C" && after.label == "C→B") ||
                    (before.label == "B→A" && after.label == "A→B")
                if ((before.phase == "HOLD" && after.phase == "RUN") || turn) {
                    pass++
                    passAt = now
                    zoomAt = now
                    expected = if (pass % 2 == 0) GimbalZoomPath(saved) else
                        GimbalZoomPath(saved.copy(a = c, c = a, durationAB = 2.0, durationBC = 1.0))
                }
                out.target?.let {
                    origin = live
                    target = it
                    motionAt = now
                    motionDuration = out.duration
                }
                assertNull(engine.failure, "smoothness=$smoothness time=$now")
                val crossedB = (before.label == "A→B" && after.label == "B→C") ||
                    (before.label == "C→B" && after.label == "B→A")
                val expectedZoom = when {
                    pass < 0 -> a.zoom
                    crossedB -> b.zoom
                    turn -> if (pass % 2 == 1) c.zoom else a.zoom
                    else -> expected.position(now - zoomAt)
                }
                assertEquals(expectedZoom, engine.consumeProgrammedZoomTarget()!!, 1e-7)
                if (!paused && pass == 1 && now - passAt >= 0.43 - 1e-9) {
                    val measured = live.copy(zoom = 1.7)
                    assertTrue(engine.pause(measured))
                    assertNull(engine.programmedZoomTarget)
                    expected = expected.remaining(now - zoomAt, measured.zoom, quantized = smoothness == 0.0)
                    zoomAt = now
                    assertTrue(engine.resume(measured))
                    assertEquals(expected.position(0.0), engine.programmedZoomTarget!!, 1e-7)
                    origin = measured
                    target = measured
                    motionAt = now
                    paused = true
                    resumeCommand = true
                }
            }
            assertTrue(pass >= 3)
            assertTrue(paused)
            engine.cancel()
            assertNull(engine.programmedZoomTarget)
        }
    }

    @Test fun acceptedLateTurnaroundRetainsEndpointUntilTheNextAdmittedLensSample() {
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true), a))
        repeat(294) { engine.tick(0.01, a) }
        assertTrue(engine.consumeProgrammedZoomTarget()!! < 3.0)
        val out = engine.tick(0.065, a)!!
        assertFalse(out.finished)
        assertEquals("B→A", engine.readout(a)!!.label)
        assertEquals(3.0, engine.programmedZoomTarget)
        engine.tick(0.01, a)
        assertEquals(3.0, engine.consumeProgrammedZoomTarget())
        assertTrue(engine.programmedZoomTarget!! < 3.0)
        assertNull(engine.failure)
    }

}
