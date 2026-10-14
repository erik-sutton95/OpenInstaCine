package com.opencapture.openinstacine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.appkit.MonitorCapturePresentation
import com.opencapture.opencine.cameracontrols.CaptureFormatChoice
import com.opencapture.opencine.cameracontrols.CaptureFormatGroup
import com.opencapture.opencine.cameracontrols.CaptureFormatPicker
import com.opencapture.opencine.cameracontrols.CaptureDrumWheel
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.core.CameraRecordingFormat
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.insta360.shell.CameraColorProfile

/** Native values keep the backend's identifiers; the shared sheet owns all chrome. */
@Composable internal fun LunaNativeCapturePanel(model: AppModel, sheet: LiveSheet, enabled: Boolean) {
    val session = model.session
    val state by session.control.state.collectAsState()
    val phase by session.phaseFlow.collectAsState()
    val current by session.nativeFormat.collectAsState()
    val available by session.nativeFormats.collectAsState()
    val color by session.nativeColor.collectAsState()
    val captured = Triple(state.snapshot?.session, state.snapshot?.epoch, phase)
    val isCurrent = { enabled && !model.operatorSession.locked &&
        session.control.state.value.snapshot?.recording?.value == com.opencapture.opencine.core.RecordingState.IDLE &&
        captured == Triple(session.control.state.value.snapshot?.session,
        session.control.state.value.snapshot?.epoch, session.phase) }
    if (sheet == LiveSheet.FORMAT) {
        val values = if (current != null && current !in available) listOfNotNull(current) + available else available
        val choices = values.map { value ->
            val dimensions = CameraRecordingFormat.Dimensions.measured(value.width, value.height)
            val rate = Rational.frameRate(value.fps)
            val format = CameraRecordingFormat.measured(dimensions, rate)
            CaptureFormatChoice(value, MonitorCapturePresentation.recordingLabel(format) ?: "Unknown",
                aspect = CaptureFormatGroup("${value.width.toDouble() / value.height}", if (value.height > value.width) "Portrait" else if (value.height == value.width) "Square" else "Landscape"),
                resolution = CaptureFormatGroup("${value.width}x${value.height}", dimensions?.let(MonitorCapturePresentation::resolutionLabel) ?: "Unknown"),
                frameRate = rate?.let { CaptureFormatGroup(it.toString(), MonitorCapturePresentation.frameRate(it) + "p") },
                isEditable = value in available)
        }
        CaptureFormatPicker(choices, current, enabled && choices.isNotEmpty(), captured,
            isCurrent = isCurrent, onSelect = { if (isCurrent()) session.setNativeRecordingFormat(it.value) })
    } else {
        val choices = listOf(CameraColorProfile.STANDARD to "Standard", CameraColorProfile.LOG to "I-Log", CameraColorProfile.DOLBY_VISION to "Dolby Vision")
        CaptureDrumWheel(choices.map { it.second }, choices.firstOrNull { it.first == color }?.second.orEmpty(),
            interactive = enabled, onSelect = { label ->
                if (isCurrent()) choices.firstOrNull { it.second == label }?.let { session.setNativeRecordingColor(it.first) }
            })
    }
}
