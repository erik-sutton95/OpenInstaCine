package com.opencapture.openinstacine.monitor.pairing

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.appkit.PairingCalloutCopy
import com.opencapture.opencine.appkit.PairingCalloutStack
import com.opencapture.opencine.appkit.PermissionGate
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter

/** The pair wizard's content: OpenCine's [PairingCalloutStack] with this app's session and copy. */
@Composable
fun PairingCallouts(model: AppModel, discovery: PermissionGate, onEnableBluetooth: () -> Unit) {
    val phase by model.session.phaseFlow.collectAsState()
    val radioOn by model.session.radioOn.collectAsState()
    PairingCalloutStack(
        cameras = model.cameras,
        coreLoaded = model.coreVersion != null,
        scanning = phase == ConnectionPhase.SCANNING,
        radioOn = radioOn,
        discovery = discovery,
        copy = PairingCalloutCopy(
            cameraNoun = "camera",
            precheck = StartupConnectionCopy.PAIRING_PRECHECK,
            stillLooking = StartupConnectionCopy.STILL_LOOKING,
        ),
        log = DiagnosticCenter::log,
        onEnableBluetooth = onEnableBluetooth,
    )
}
