package com.opencapture.openinstacine.monitor

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.monitorui.monitorReadoutShadow
import android.os.SystemClock
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.EvComp
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlin.math.cos
import kotlin.math.sin

internal typealias CameraExposureMeter = com.opencapture.opencine.cameracontrols.MonitorOperatorExposureReading

@Composable
internal fun LiveCameraExposureMeter(raw: () -> Int, available: Boolean, feed: ChromeRect, mode: PocketDispMode,
    modifier: Modifier = Modifier, avoid: ChromeRect? = null) {
    com.opencapture.opencine.cameracontrols.MonitorOperatorExposureMeter(raw(), available, feed, mode, modifier, avoid)
}

/** iOS `CameraEVMeterOverlay.pictureEV`: metered EV from the live picture for a camera that reports none (raw, or -1). */
internal fun pictureMeteredEv(session: PocketCameraSession, assist: LiveAssistState, status: CameraStatus): Int {
    if (!assist.evMeterFromPicture) return -1
    val bundle = assist.scopeBundle
    val picture = com.opencapture.opencine.media.MonitorNDFilterRecommendation.pictureStops(bundle.samples.histogramLuma, bundle.transfer) ?: return -1
    val evComp = EvComp.fromRaw(status.evComp)?.takeIf { status.expoMode == CameraCommands.EXPO_AUTO }
    // Image-estimated: callers use it only when the camera reports no metered EV.
    val stops = session.pictureEV.stops(
        picture, session.pictureEVSource(bundle.transfer), evComp?.thirds?.div(3.0), SystemClock.elapsedRealtime() / 1000.0)
    return EvComp.fromThirds(Math.round(stops.value!! * 3).toInt()).rawValue
}
