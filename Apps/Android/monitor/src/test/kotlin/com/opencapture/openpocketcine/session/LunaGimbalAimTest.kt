package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.core.CameraGimbalAngle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LunaGimbalAimTest {
    @Test fun levelKeepsYawAndCancelsHeadPitch() {
        // Handle pitch 12, head 5 above the horizon: level is handle pitch 7.
        val target = LunaGimbalAim.levelTarget(CameraGimbalAngle(pitch = 12.0, yaw = -170.0), 5.0, 2.0)
        assertEquals(7.0, target.pitchDeg, 1e-9)
        assertEquals(190.0, target.yawDeg, 1e-9) // unwrapped past the -92 gap
        val (pitch, yaw) = LunaGimbalAim.setAngle(target)
        assertEquals(7.0, pitch, 1e-9)
        assertEquals(-170.0, yaw, 1e-9)
        assertTrue(LunaGimbalAim.reached(CameraGimbalAngle(7.3, -170.4), target))
        assertEquals(-57.0, LunaGimbalAim.setAngle(target.copy(pitchDeg = -80.0)).first, 1e-9)
    }

    @Test fun programPoseFollowsStraightLegs() {
        val a = GimbalWaypoint(0.0, 0.0, 1.0)
        val b = GimbalWaypoint(20.0, 10.0, 1.0)
        val c = GimbalWaypoint(20.0, -10.0, 1.0)
        val take = GimbalProgram(a, b, c, durationAB = 4.0, durationBC = 2.0)
        assertEquals(6.0, LunaGimbalAim.programDuration(take), 1e-9)
        assertEquals(a, LunaGimbalAim.programPose(take, 0.0))
        assertEquals(10.0, LunaGimbalAim.programPose(take, 2.0)!!.yawDeg, 1e-9)
        assertEquals(0.0, LunaGimbalAim.programPose(take, 5.0)!!.pitchDeg, 1e-9)
        assertEquals(c.pitchDeg, LunaGimbalAim.programPose(take, 6.0)!!.pitchDeg, 1e-9)
    }
}
