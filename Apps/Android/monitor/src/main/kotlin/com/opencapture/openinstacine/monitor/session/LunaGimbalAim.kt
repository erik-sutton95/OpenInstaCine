package com.opencapture.openinstacine.monitor.session

import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import com.opencapture.opencine.motion.GimbalWaypoint

/** Absolute-angle gimbal targets (cmd 226 SET_ANGLE / GET_ANGLE), iOS `CameraSessionControls` 309049f. */
object LunaGimbalAim {
    /** A GET_ANGLE reading as a shell waypoint (yaw unwrapped across the stop gap). */
    fun waypoint(angle: CameraGimbalAngle, zoom: Double) =
        GimbalWaypoint(GimbalWaypoint.unwrapYaw(angle.yaw), angle.pitch, zoom, -angle.pitch)

    /** Level keeps yaw; SET_ANGLE is handle relative, so pitch is handle pitch minus head world pitch. */
    fun levelTarget(angle: CameraGimbalAngle, headPitchDeg: Double, zoom: Double) =
        waypoint(angle.copy(pitch = angle.pitch - headPitchDeg), zoom)
}
