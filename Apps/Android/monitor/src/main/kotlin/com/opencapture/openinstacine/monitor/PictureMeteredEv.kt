package com.opencapture.openinstacine.monitor

import android.os.SystemClock
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.EvComp
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.openinstacine.monitor.session.PocketCameraSession

/** iOS `syncLiveMonitorColor`: a camera that meters no EV (the Luna) reads it from the picture. */
internal fun LiveAssistState.followMeteredEvSource(reportsMeteredEV: Boolean) {
    evMeterFromPicture = !reportsMeteredEV
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
