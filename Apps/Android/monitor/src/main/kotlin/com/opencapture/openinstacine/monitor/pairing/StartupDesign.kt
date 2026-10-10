package com.opencapture.openinstacine.monitor.pairing

import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.opencapture.openinstacine.monitor.LiveDesign

/** Startup chrome colors still used outside the pairing pages (LUT picker, app backdrop). */
object StartupColors {
    val destructive: Color = Color(0.930f, 0.267f, 0.267f)
    val backdropBase: Color = LiveDesign.background
}

fun Modifier.startupBackdrop(): Modifier = background(StartupColors.backdropBase)

/** Vendor-app interference copy for the pairing callouts. */
object StartupConnectionCopy {
    // The Insta360 app on any nearby phone holds the Luna (upstream names DJI Frame Tap and Mimo here).
    const val PAIRING_PRECHECK = "Before pairing, force quit the Insta360 app."
    const val STILL_LOOKING = "Close the Insta360 app on every phone near the camera. Make sure the camera is on and activated, then move closer."
}
