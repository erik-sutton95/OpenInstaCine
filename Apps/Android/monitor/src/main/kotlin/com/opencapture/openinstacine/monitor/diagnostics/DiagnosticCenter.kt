package com.opencapture.openinstacine.monitor.diagnostics

import android.content.Context
import com.opencapture.opencine.appkit.diagnostics.DiagnosticCamera
import com.opencapture.opencine.appkit.diagnostics.DiagnosticCenterRuntime
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.session.PocketCameraSession

/**
 * On-device journal, exceptions, and a shareable report: OpenCine's [DiagnosticCenterRuntime]
 * with this app's host. No camera access point stays readable.
 */
object DiagnosticCenter :
    DiagnosticCenterRuntime<PocketCameraSession>(
        host = AppDiagnostics.host,
        incidents = AppDiagnostics.incidents,
        isSafeNetwork = { false },
        vpnActive = LocalVPNProbe::isActive,
        camera = { session ->
            DiagnosticCamera(
                family = session.connectedCamera?.model?.family ?: "none",
                model = session.connectedCamera?.model?.name ?: "none",
                phase = session.phase.name.lowercase(),
            )
        },
    ) {
    override fun installHost(context: Context) {
        AppDiagnostics.reporting.noteFeedUpscaler(OperatorPrefs.feedUpscaler(context).label)
        AppDiagnostics.reporting.install(context.applicationContext, AppDiagnostics.incidents)
        AppDiagnostics.manualReport.install(context.applicationContext)
    }
}
