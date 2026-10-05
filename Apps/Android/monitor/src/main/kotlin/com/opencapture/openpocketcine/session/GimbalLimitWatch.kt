package com.opencapture.openpocketcine.session

/** Rising-edge pulse when a commanded axis moves then stops at a mechanical end. */
data class GimbalLimitContact(val pan: Boolean = false, val tilt: Boolean = false) {
    val isEmpty: Boolean
        get() = !pan && !tilt

    fun union(other: GimbalLimitContact) =
        GimbalLimitContact(pan = pan || other.pan, tilt = tilt || other.tilt)
}

