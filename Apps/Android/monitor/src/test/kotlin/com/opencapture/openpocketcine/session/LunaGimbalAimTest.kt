package com.opencapture.openpocketcine.session

import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import com.opencapture.opencine.motion.GimbalWaypoint
import org.junit.Assert.assertEquals
import org.junit.Test

class LunaGimbalAimTest {
    @Test fun levelKeepsYawAndCancelsHeadPitch() {
        // Handle pitch 12, head 5 above the horizon: level is handle pitch 7.
        val target = LunaGimbalAim.levelTarget(CameraGimbalAngle(pitch = 12.0, yaw = -170.0), 5.0, 2.0)
        assertEquals(7.0, target.pitchDeg, 1e-9)
        assertEquals(190.0, target.yawDeg, 1e-9) // unwrapped past the -92 gap
        assertEquals(GimbalWaypoint(190.0, 7.0, 2.0, -7.0), target)
        // SET_ANGLE's wrap and reach moved to OpenCine `LunaMotionServiceTest.aimWrapsYawAndKeepsPitchInsideTheDeclaredReach`,
        // arrival to `LunaMotionServiceTest.arrivalIsWithinHalfADegreeOnEachAxisAcrossTheWrap`.
    }
}
