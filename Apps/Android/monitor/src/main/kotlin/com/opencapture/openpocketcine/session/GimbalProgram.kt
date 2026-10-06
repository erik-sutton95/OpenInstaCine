package com.opencapture.openpocketcine.session

import com.opencapture.opencine.motion.GimbalWaypoint
import com.opencapture.opencine.motion.GimbalWaypointOverlay
import com.opencapture.opencine.motion.MotionBounds

// The shell reach on the shared waypoint (Swift `HeadTrack.Reach`): pan one arc from -48 through
// front to 225, tilt -44 to 70.
val GimbalWaypoint.Companion.PAN_MIN_DEG: Double get() = -48.0
val GimbalWaypoint.Companion.PAN_MAX_DEG: Double get() = 225.0
val GimbalWaypoint.Companion.TILT_MIN_DEG: Double get() = -44.0
val GimbalWaypoint.Companion.TILT_MAX_DEG: Double get() = 70.0

private val shellReach = MotionBounds(
    GimbalWaypoint.PAN_MIN_DEG..GimbalWaypoint.PAN_MAX_DEG,
    GimbalWaypoint.TILT_MIN_DEG..GimbalWaypoint.TILT_MAX_DEG,
)

fun GimbalWaypoint.Companion.unwrapYaw(rawDeg: Double): Double = unwrapYaw(rawDeg, shellReach)

/** Waypoint marks on the live frame use the shell lens's widest horizontal field of view. */
fun GimbalWaypointOverlay.project(waypoint: GimbalWaypoint, live: GimbalWaypoint, aspect: Double): Triple<Double, Double, Boolean> =
    project(waypoint, live, aspect, wideHFovDeg = 84.0)
