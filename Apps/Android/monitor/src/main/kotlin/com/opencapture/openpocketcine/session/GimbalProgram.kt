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

enum class GimbalMode(private val defaultLabel: String) {
    FOLLOW("Follow"),
    TILT_LOCKED("Tilt locked"),
    FPV("FPV"),
    DIRECTION_LOCK("Direction Lock"),
    ;

    val label: String get() = defaultLabel

    /** The session's brand name for this mode (Insta360 Roll Lock / FPV-V). */
    fun label(profile: CameraProfile): String = profile.gimbalLabels[this] ?: defaultLabel

    companion object {
        val pickerOrder = listOf(FOLLOW, TILT_LOCKED, FPV, DIRECTION_LOCK)
    }
}

enum class GimbalSpeed(val wire: Int, val label: String) {
    FAST(0, "Fast"),
    DEFAULT(1, "Default"),
    SLOW(2, "Slow"),
    ;

    companion object {
        val pickerOrder = listOf(SLOW, DEFAULT, FAST)

        fun fromWire(value: Int): GimbalSpeed? = entries.firstOrNull { it.wire == value }
    }
}

enum class GimbalRamp(val raw: Int, val label: String, val tau: Double) {
    OFF(0, "Off", 0.0),
    SOFT(1, "Soft", 0.35),
    MEDIUM(2, "Medium", 0.18),
    ;

    companion object {
        val pickerOrder = listOf(OFF, SOFT, MEDIUM)

        fun fromRaw(value: Int): GimbalRamp = entries.firstOrNull { it.raw == value } ?: OFF
    }
}

/** Stick double-tap and gamepad Circle/B: body recenter or a world-level snap. */
enum class GimbalDoubleTap(val raw: Int, val label: String) {
    RECENTER(0, "Recenter"),
    LEVEL(1, "Level"),
    ;

    companion object {
        val pickerOrder = listOf(RECENTER, LEVEL)

        fun fromRaw(value: Int): GimbalDoubleTap = entries.firstOrNull { it.raw == value } ?: RECENTER
    }
}

object GimbalHudCopy {
    const val POSE_NOT_READY = "Gimbal pose not ready"
    const val NEED_AB = "Set A and B to run"
    const val HOLD_STILL = "Hold the gimbal still"
    const val TITLE = "Gimbal"
    const val MODE = "Mode"
    const val SPEED = "Speed"
    const val RAMP = "Ramp"
    const val PROGRAMMED = "Motion Control"
    const val RUN = "Start"
    const val STOP = "Stop"
}
