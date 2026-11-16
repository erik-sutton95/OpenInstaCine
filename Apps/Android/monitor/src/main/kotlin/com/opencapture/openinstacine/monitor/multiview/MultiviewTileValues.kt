package com.opencapture.openinstacine.monitor.multiview

import com.opencapture.monitorui.MonitorTimecodeFormat
import com.opencapture.opencine.appkit.MultiviewReadout
import com.opencapture.opencine.appkit.MultiviewTally
import com.opencapture.opencine.appkit.MultiviewTileReadings
import com.opencapture.opencine.appkit.label
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.media.storageReadout
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.storageReadout
import com.opencapture.openinstacine.monitor.session.LunaShellMapping

/**
 * The tile readouts as Live View words them (iOS `MultiviewReadings`, Pocket Android
 * `multiviewTileReadouts`): format, storage, timecode, take length and ISO, SHUTTER, WB and FOCUS,
 * from the tile session's own status and the member's common session. No polling of its own.
 */
internal object MultiviewTileValues {
    fun readings(camera: NearbyCamera, status: CameraStatus, snapshot: CameraSnapshot?, hasPicture: Boolean) =
        MultiviewTileReadings(
            name = camera.name,
            model = camera.model,
            format = format(status),
            storage = storage(status, snapshot),
            // The Luna reports no body clock: this is the phone-derived timecode Live View shows.
            timecode = MonitorTimecodeFormat.label(snapshot),
            readouts = readouts(status),
            recordingSeconds = status.recordElapsedSec.coerceAtLeast(0),
            power = snapshot?.power,
            hasPicture = hasPicture,
            accessibilityValue = if (hasPicture) "Live" else "Reconnecting",
        )

    fun format(status: CameraStatus): String {
        val resolution = status.resolutionLabel.takeUnless { status.resolutionCode < 0 || it.isEmpty() } ?: DASH
        val rate = if (status.fps > 0) "${status.fps}p" else DASH
        val color = if (status.colorMode < 0) DASH else CameraCommands.colorLabel(status.colorMode, profile = LunaShellMapping.profile.labels)
        return "$resolution $rate · $color"
    }

    fun storage(status: CameraStatus, snapshot: CameraSnapshot?): String =
        (snapshot?.storage?.storageReadout ?: status.storageReadout)?.free ?: MultiviewTally.UNAVAILABLE

    fun readouts(status: CameraStatus): List<MultiviewReadout> = listOf(
        MultiviewReadout("ISO", if (status.iso > 0) status.iso.toString() else DASH),
        MultiviewReadout("SHUTTER", if (status.shutterDenom > 0) "1/${status.shutterDenom}" else DASH),
        MultiviewReadout("WB", status.wbLabel),
        MultiviewReadout("FOCUS", status.focusLabel),
    )

    private const val DASH = "\u2014"
}

/**
 * The tiles' Auto LUT rule (iOS `MultiviewSession.conversion` and `previewProfile`): it follows what
 * the picture carries, as Live View's. On Android, Live View grades the I-Log preview as flat (the
 * app has no Color Recovery preference; iOS's flat I-Log preview preference defaults to the same,
 * since firmware 1.1.15 measures the I-Log phone preview flat), so a tile does the same and never
 * grades a picture Live View would not.
 */
internal object MultiviewLut {
    private const val ILOG = "I-Log"

    /** The bundled conversion for a picture's color profile; null when it needs none. */
    fun conversion(colorProfile: String): String? = if (colorProfile == ILOG) "I-Log to Rec.709" else null

    /** What the picture carries for a recorded profile (Live View's rule on Android). */
    fun previewProfile(recorded: String): String = recorded

    /** The color mode the tile's Auto LUT grades from: Live View's `monitorColorMode`. */
    fun previewColorMode(status: CameraStatus): Int = status.monitorColorMode
}
