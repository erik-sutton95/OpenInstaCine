package com.opencapture.openpocketcine.session

import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import kotlin.math.abs

/** Absolute-angle gimbal targets (cmd 226 SET_ANGLE / GET_ANGLE), iOS `CameraSessionControls` 309049f. */
object LunaGimbalAim {
    /** fw 1.1.15 pitch reach; SET_ANGLE routes yaw around the stop itself. */
    val PITCH_RANGE = -57.0..90.0

    /** A GET_ANGLE reading as a shell waypoint (yaw unwrapped across the stop gap). */
    fun waypoint(angle: CameraGimbalAngle, zoom: Double) =
        GimbalWaypoint(GimbalWaypoint.unwrapYaw(angle.yaw), angle.pitch, zoom, -angle.pitch)

    /** Level keeps yaw; SET_ANGLE is handle relative, so pitch is handle pitch minus head world pitch. */
    fun levelTarget(angle: CameraGimbalAngle, headPitchDeg: Double, zoom: Double) =
        waypoint(angle.copy(pitch = angle.pitch - headPitchDeg), zoom)

    /** SET_ANGLE arguments (pitch, yaw): yaw back to +-180, pitch inside the reach. */
    fun setAngle(target: GimbalWaypoint): Pair<Double, Double> =
        target.pitchDeg.coerceIn(PITCH_RANGE) to Math.IEEEremainder(target.yawDeg, 360.0)

    fun reached(angle: CameraGimbalAngle, target: GimbalWaypoint): Boolean =
        abs(Math.IEEEremainder(angle.yaw - target.yawDeg, 360.0)) <= 0.5 && abs(angle.pitch - target.pitchDeg) <= 0.5

    /** Target pose [time] s into a take: the rounded-corner curve with smoothness, straight legs otherwise. */
    fun programPose(take: GimbalProgram, time: Double): GimbalWaypoint? {
        val a = take.a ?: return null
        val b = take.b ?: return null
        GimbalProgramCurve.create(take)?.let { return it.position(time) }
        val c = take.c
        if (time < take.durationAB || c == null) return GimbalMoveEngine.lerp(a, b, time / take.durationAB)
        return GimbalMoveEngine.lerp(b, c, (time - take.durationAB) / take.durationBC)
    }

    fun programDuration(take: GimbalProgram): Double = take.durationAB + if (take.c == null) 0.0 else take.durationBC
}
