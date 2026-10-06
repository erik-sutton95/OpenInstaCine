package com.opencapture.openinstacine.monitor

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import com.opencapture.opencine.motion.GimbalWaypoint
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import com.opencapture.opencine.motion.WorldLevelSnap
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Characterization of the session facade's gimbal: the held stick's rate stream, the release,
 * recenter and flip, the GET_ANGLE poll behind the live pose, and SET_ANGLE when levelling.
 */
@RunWith(AndroidJUnit4::class)
class GimbalSessionTest {
    private val backend = FakeShellBackend()
    private lateinit var session: PocketCameraSession

    @Before fun open() { session = liveSession(backend) }
    @After fun close() { onMain { session.close() } }

    private fun note() = onMain { session.controlNote.value }
    private fun sticks(pan: Double, tilt: Double) = backend.calls("gimbalStick").filter { it.args == listOf(pan, tilt) }

    @Test fun heldStickStreamsShapedRatesEvery50msAndRestSendsOneRelease() {
        // Ease-in: 0.5 → 0.25 of full speed, −1 → −1.
        onMain { session.updateGimbalStick(0.5f, -1f) }
        assertTrue(waitUntil { sticks(0.25, -1.0).size >= 3 })
        val times = sticks(0.25, -1.0).map { it.atMs }
        times.zipWithNext().forEach { (a, b) -> assertTrue(b - a >= 45, "never faster than one MOVE per 50 ms: ${b - a} ms") }

        // Inside the deadzone the held stick keeps streaming rest.
        onMain { session.updateGimbalStick(0.01f, 0f) }
        assertTrue(waitUntil { sticks(0.0, 0.0).size >= 2 })

        val before = backend.calls("gimbalStick").size
        onMain { session.endGimbalStick() }
        SystemClock.sleep(300)
        val after = backend.calls("gimbalStick").drop(before)
        assertEquals(listOf(listOf<Any?>(0.0, 0.0)), after.map { it.args }, "one release, and the stream ends")
    }

    @Test fun recenterAndFlipSendTheirActionsAndSayWhenTheCameraMissesThem() {
        onMain { session.recenterGimbal() }
        assertTrue(waitUntil { backend.calls("gimbalRecenter").size == 1 })
        onMain { session.flipGimbal() }
        assertTrue(waitUntil { backend.calls("gimbalFlip").size == 1 })
        backend.accepts = false
        onMain { session.recenterGimbal() }
        assertTrue(waitUntil { note() == "Recenter did not reach the camera." })
        onMain { session.flipGimbal() }
        assertTrue(waitUntil { note() == "Flip did not reach the camera." })
    }

    @Test fun theAnglePollBecomesTheLivePoseUntilItGoesStale() {
        backend.angle = CameraGimbalAngle(pitch = -12.5, yaw = 33.0)
        assertTrue(waitUntil { onMain { session.liveGimbalWaypoint } == GimbalWaypoint(33.0, -12.5, 1.0, 12.5) })
        val polls = backend.calls("gimbalAngle").map { it.atMs }
        polls.zipWithNext().forEach { (a, b) -> assertTrue(b - a >= 95, "GET_ANGLE every 100 ms: ${b - a} ms") }
        backend.angle = null
        assertTrue(waitUntil(2_000) { onMain { session.liveGimbalWaypoint } == null }, "older than 0.5 s is no pose")
    }

    @Test fun levelSendsOneSetAngleWithPitchInReachAndYawWrapped() {
        onMain { session.levelGimbalToWorld(refine = false) }
        assertTrue(waitUntil { note() == WorldLevelSnap.NO_LEVEL_DATA })
        assertTrue(backend.calls("gimbalSetAngle").isEmpty())

        // Head 30 deg down at handle pitch 80: level asks 110, kept at the 90 deg reach. Yaw −170
        // unwraps to 190 across the stop and goes back out as −170.
        backend.headPitch = -30.0
        backend.angle = CameraGimbalAngle(pitch = 80.0, yaw = -170.0)
        assertTrue(waitUntil { onMain { session.liveGimbalWaypoint } != null })
        onMain { session.levelGimbalToWorld(refine = false) }
        assertTrue(waitUntil { backend.calls("gimbalSetAngle").size == 1 })
        assertEquals(listOf<Any?>(90.0, -170.0), backend.calls("gimbalSetAngle").single().args)
        SystemClock.sleep(300)
        assertEquals(1, backend.calls("gimbalSetAngle").size, "the aim waits for the head, it does not resend")
    }
}
