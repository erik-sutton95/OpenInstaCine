package com.opencapture.openinstacine.monitor.session

import com.opencapture.opencine.vocabulary.CameraLabelProfile
import com.opencapture.opencine.vocabulary.MediaRoute

/**
 * Per-integration vocabulary and media addressing for one camera session (STATE-01). Replaces the
 * launch-time globals (mode, colour, gimbal and focus label overrides, `MediaHTTP.host/directPath`),
 * so two sessions with different integrations never read each other's names or media host.
 * Defaults are the DJI shell's: the vocabulary's own names ([CameraLabelProfile.standard]).
 */
data class CameraProfile(
    val labels: CameraLabelProfile = CameraLabelProfile.standard,
    val media: MediaRoute = MediaRoute.CAMERA_SOFT_AP,
) {
    companion object {
        val DJI = CameraProfile()
    }
}
