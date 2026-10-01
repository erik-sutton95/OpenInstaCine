package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.media.MediaRoute

/**
 * Per-integration vocabulary and media addressing for one camera session (STATE-01). Replaces the
 * launch-time globals (mode, colour, gimbal and focus label overrides, `MediaHTTP.host/directPath`),
 * so two sessions with different integrations never read each other's names or media host.
 * Defaults are the DJI shell's.
 */
data class CameraProfile(
    val shootingModeLabels: Map<Int, String> = emptyMap(),
    val colorLabels: Map<Int, String> = emptyMap(),
    val gimbalLabels: Map<GimbalMode, String> = emptyMap(),
    /** The FOCUS drum and chip list, in drum order. */
    val focusLabels: List<String> = FocusOption.entries.map { it.chip },
    val media: MediaRoute = MediaRoute.DJI,
) {
    companion object {
        val DJI = CameraProfile()
    }
}
