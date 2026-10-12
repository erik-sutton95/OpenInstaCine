package com.opencapture.openinstacine.monitor.pairing

import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import com.opencapture.openinstacine.monitor.LiveDesign

/** The app backdrop behind the shell. */
fun Modifier.startupBackdrop(): Modifier = background(LiveDesign.background)

/** Vendor-app interference copy for the pairing callouts. */
object StartupConnectionCopy {
    // The Insta360 app on any nearby phone holds the Luna (upstream names DJI Frame Tap and Mimo here).
    const val PAIRING_PRECHECK = "Before pairing, force quit the Insta360 app."
    const val STILL_LOOKING = "Close the Insta360 app on every phone near the camera. Make sure the camera is on and activated, then move closer."
}
