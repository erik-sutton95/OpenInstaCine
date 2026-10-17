package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.MonitorOperatorMeteringTile
import com.opencapture.openinstacine.monitor.session.PocketCameraSession

/** The native metering slot over the same captured scene facts and setter as the live surface. */
internal fun PocketCameraSession.nativeMeteringSource(face: Boolean?, isCurrent: () -> Boolean): MonitorOperatorMeteringTile? {
    if (!controlCapabilities().faceMetering.isOffered) return null
    return MonitorOperatorMeteringTile(face, {
        isCurrent() && controlCapabilities().faceMetering.isOffered
    }) { face?.let { setFaceMetering(!it) } }
}
