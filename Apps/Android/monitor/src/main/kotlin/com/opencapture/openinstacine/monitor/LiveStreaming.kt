package com.opencapture.openinstacine.monitor

import android.content.Context
import com.opencapture.opencine.appkitnative.LiveStreamComposition
import com.opencapture.opencine.appkitnative.LiveStreamCoordinator
import com.opencapture.opencine.appkitnative.LiveStreamSource
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.opencine.insta360.luna.LunaRoute
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.runtime.MonitorCleanPictureTap
import com.opencapture.opencine.streaming.StreamConnectionRoute
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlinx.coroutines.CoroutineScope

/**
 * Live streaming's host values for the monitor camera (one camera; the app has no program
 * switching). Everything here reads what the session already knows and never sends a camera
 * command.
 */
internal object LiveStreaming {
    /**
     * How this phone reaches the live camera: the camera's own Wi-Fi, or the Wi-Fi or hotspot setup
     * the camera joined (station mode). `null` while no camera is live or the backend is not a Luna
     * port (the debug local replay). A setup's route counts only once the camera answers away from
     * its own access point address; otherwise the phone is on the camera's Wi-Fi.
     */
    fun route(live: Boolean, requested: LunaRoute?, cameraHost: String?): StreamConnectionRoute? = when {
        !live || requested == null -> null
        requested is LunaRoute.Station && cameraHost != null && cameraHost != LunaBackend.CAMERA_HOST ->
            if (requested.network.hotspot) StreamConnectionRoute.DEVICE_HOTSPOT else StreamConnectionRoute.SHARED_WIFI
        else -> StreamConnectionRoute.CAMERA_WIFI
    }

    /**
     * The live picture as the decoder reports it; `null` until a picture is decoded. The Luna's
     * preview rate is not reported to this app, so the rate is left unstated.
     */
    fun source(hasPicture: Boolean, width: Int, height: Int): LiveStreamSource? =
        if (hasPicture && width > 0 && height > 0) LiveStreamSource(width, height, null, null) else null

    /** The coordinator over [session]'s connection and picture, storing under this install's id. */
    fun coordinator(
        context: Context,
        session: PocketCameraSession,
        cleanPicture: MonitorCleanPictureTap,
        scope: CoroutineScope,
    ): LiveStreamCoordinator {
        val storage = "${context.packageName}.live-stream"
        return LiveStreamComposition.coordinator(
            context, preferencesFile = storage, keystoreAlias = storage, cleanPicture = cleanPicture,
            route = {
                route(session.phase == ConnectionPhase.LIVE && session.connectedCamera != null,
                    session.requestedRoute, session.cameraHost)
            },
            source = {
                source(session.decoder.hasPicture.value, session.decoder.pictureWidth, session.decoder.pictureHeight)
            },
            scope = scope,
        )
    }
}
