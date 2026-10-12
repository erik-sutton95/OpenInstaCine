package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.appkit.DiscoveryRestart
import com.opencapture.opencine.appkit.MonitorActivityLaunch
import com.opencapture.opencine.appkit.MonitorAppRoot
import com.opencapture.opencine.appkit.MonitorLaunchBrand
import com.opencapture.opencine.appkit.MonitorReportsOffer
import com.opencapture.opencine.appkit.retainedMonitorRoot
import androidx.compose.ui.graphics.Color
import com.opencapture.opencine.appkit.applyMonitorSystemBars
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.appkit.rememberOperatorHaptics
import com.opencapture.opencine.runtime.MonitorHDRDisplay
import com.opencapture.openinstacine.monitor.diagnostics.AppDiagnostics
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.opencapture.opencine.appkit.AppShell
import com.opencapture.opencine.appkit.PairingWizard
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.opencine.appkit.ShellActions
import com.opencapture.opencine.appkit.ShellBrand
import com.opencapture.openinstacine.monitor.diagnostics.ManualProblemReportDialog
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.openinstacine.monitor.pairing.PairingCallouts
import com.opencapture.opencine.appkit.PermissionGate
import com.opencapture.openinstacine.monitor.pairing.rememberPermissionGate
import com.opencapture.openinstacine.monitor.pairing.startupBackdrop

open class MainActivity : ComponentActivity() {
    private val launch = MonitorActivityLaunch()
    lateinit var model: AppModel
        private set
    var hideSystemNavigation = false
    var playbackHidesSystemNavigation = false

    fun updateSystemBars() {
        applyMonitorSystemBars(window, hideSystemNavigation || playbackHidesSystemNavigation)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen().setKeepOnScreenCondition { !launch.firstFrameDrawn }
        super.onCreate(savedInstanceState)
        // One model per task: a recreated activity keeps the session; finishing closes it.
        model = retainedMonitorRoot { AppModel(applicationContext).also(AppModel::prepareStartup) }
        model.gimbalGamepad.ensureListening(this, model)
        launch.setContent(this) {
            OpenInstaCineTheme {
                val haptics = rememberOperatorHaptics { model.hapticsEnabled }
                CompositionLocalProvider(LocalOperatorHaptics provides haptics) {
                    OpenInstaCineApp(model)
                }
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        updateSystemBars()
    }

    override fun onPause() {
        if (::model.isInitialized) model.shell.setSceneActive(false)
        AppDiagnostics.manualReport.setForeground(false)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        AppDiagnostics.manualReport.setForeground(true)
        if (::model.isInitialized) {
            model.shell.setSceneActive(true)
            model.gimbalGamepad.ensureListening(this, model)
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (::model.isInitialized && model.gimbalGamepad.onMotion(event, model)) return true
        return super.dispatchGenericMotionEvent(event)
    }

    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (::model.isInitialized && model.gimbalGamepad.onKey(event, model)) return true
        return super.dispatchKeyEvent(event)
    }
}

@Composable
private fun OpenInstaCineApp(model: AppModel) {
    val shell by model.shell.state.collectAsState()
    val context = LocalContext.current
    var showProblemReport by remember { mutableStateOf(false) }
    var showReportingPrivacy by remember { mutableStateOf(false) }
    val activity = LocalActivity.current
    lateinit var discovery: PermissionGate
    val enableBluetooth =
        rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            if (discovery.granted) model.session.startScan()
        }
    fun requestBluetoothOn() {
        // Without Nearby devices the enable prompt throws; Bluetooth settings still work.
        runCatching { enableBluetooth.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) }
            .recoverCatching { activity?.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) }
            .onFailure { DiagnosticCenter.log("warning", "ble", "enable", "bluetooth enable unavailable ${it.javaClass.simpleName}") }
    }
    discovery = rememberPermissionGate("discovery", DiscoveryPermissions.discovery()) {
        beginDiscovery(model) { requestBluetoothOn() }
    }

    LaunchedEffect(Unit) {
        if (discovery.granted) {
            beginDiscovery(model, onBluetoothOff = { requestBluetoothOn() })
        } else if (!discovery.needsSettings) {
            discovery.request()
        }
    }

    val showLive = shell.monitor != null
    LaunchedEffect(model.hdrDisplayActive, activity) {
        MonitorHDRDisplay.apply(activity, enabled = model.hdrDisplayActive)
    }
    val hideNavigation = showLive && shell.cover == null
    LaunchedEffect(activity, hideNavigation) {
        (activity as? MainActivity)?.hideSystemNavigation = hideNavigation
        (activity as? MainActivity)?.updateSystemBars()
    }

    MonitorAppRoot(
        brand = MonitorLaunchBrand(R.drawable.opc_app_logo, MonitorConfiguration.identity.appName, Color(0xFF0E0E0E),
            BrandColors.ink, OpcFonts.sora),
        keepScreenAwake = model.keepScreenAwake,
        reports = MonitorReportsOffer(AppDiagnostics.consent, AppDiagnostics.reporting, AppDiagnostics.host.product) {
            model.legal = LegalKind.PRIVACY
        },
        reportsAllowed = !showLive && model.legal != LegalKind.PRIVACY,
        // Knowing about screen recording only dims the HDR boost.
        onScreenRecording = { model.screenCaptured = it },
    ) {
        Box(Modifier.fillMaxSize().startupBackdrop()) {
            val cameras by model.cameras.state.collectAsState()
            val phase by model.session.phaseFlow.collectAsState()
            val radioOn by model.session.radioOn.collectAsState()
            AppShell(
                model.shell,
                // The Luna integration declares its nearby tap (pair at once) and setup naming (none).
                ShellBrand(MonitorConfiguration.identity.wordmark),
                ShellActions(
                    diagnostics = { DiagnosticCenter.shareReport(context, model.session) },
                    reportProblem = { showProblemReport = true },
                ),
                monitor = { LiveViewScreen(model) },
                page = { cover -> ShellPage(model, cover) },
                coverPresentation = com.opencapture.opencine.appkit.ShellCoverPresentation.SHELL,
                pairingFlow = pairingWizard(
                    label = PairingWizard.phaseLabel(
                        when {
                            cameras.attempts.isEmpty() -> ConnectionPhase.SCANNING
                            phase == ConnectionPhase.IDLE -> ConnectionPhase.CONNECTING_GATT
                            else -> phase
                        },
                    ),
                    joinedNetwork = model.session.joinedSSID, vpnActive = LocalVPNProbe.isActive(context),
                    granted = discovery.granted, needsSettings = discovery.needsSettings, radioOn = radioOn,
                ).flow(
                    model.cameras, onDone = model.shell::endPairing, rescan = model.session::startScan,
                    onBlocker = { if (!discovery.granted) discovery.request() else requestBluetoothOn() },
                    content = { PairingCallouts(model, discovery) { requestBluetoothOn() } },
                ),
            )
            MonitorConfiguration.identity.sourceLabel?.let { label ->
                if (showLive) Text(label, color = BrandColors.accent, style = LiveType.mono(10f), modifier = Modifier.align(Alignment.TopCenter).background(BrandColors.background).padding(horizontal = 8.dp, vertical = 3.dp))
            }
            model.legal?.let { kind -> if (!showLive) LegalDocumentScreen(kind) { model.legal = null } }
        }
    }
    if (showProblemReport) {
        ManualProblemReportDialog(model = model, onClose = { showProblemReport = false }, onPrivacy = { showReportingPrivacy = true })
    }
    if (showReportingPrivacy) {
        Dialog(onDismissRequest = { showReportingPrivacy = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LegalDocumentScreen(kind = LegalKind.PRIVACY, onClose = { showReportingPrivacy = false })
        }
    }
}

/**
 * The pair wizard in OpenInstaCine's words (the Android pair page it has always shown): the Luna
 * pages, and Nearby devices or Bluetooth as the primary action while discovery cannot run.
 */
internal fun pairingWizard(
    label: String,
    joinedNetwork: String?,
    vpnActive: Boolean,
    granted: Boolean,
    needsSettings: Boolean,
    radioOn: Boolean,
) = PairingWizard(
    bodies = listOf(
        "Turn the Luna on and keep this phone nearby. It shows up by the last characters of its serial number.",
        "If the camera asks to allow this phone, tap Allow on its screen. First-time pairing can wait up to 90 seconds.",
        "We read the camera's Wi-Fi over Bluetooth, then join it for you.",
        "Exposure, LUTs and scopes go live as soon as the video link is up.",
    ),
    approveLines = listOf("Look for the connection request", "Tap Allow on the camera screen"),
    joinLines = listOf(
        "Leave the camera on. It brings up its own 5 GHz Wi-Fi",
        "Close the Insta360 app on other phones so the camera is free",
    ),
    label = label,
    joinedNetwork = joinedNetwork,
    vpnActive = vpnActive,
    blocker = when {
        !granted && needsSettings -> "Open Settings"
        !granted -> "Allow ${DiscoveryPermissions.settingsName(DiscoveryPermissions.discovery()).lowercase()}"
        !radioOn -> "Turn Bluetooth on"
        else -> null
    },
)

/** The Luna backend ignores a scan while it connects. */
private val DISCOVERY_RESTART = DiscoveryRestart.ANY_TIME

/** Permission granted or Bluetooth on: look again when the integration allows it now. */
private fun beginDiscovery(model: AppModel, onBluetoothOff: () -> Unit = {}) {
    if (DISCOVERY_RESTART.allows(model.cameras.state.value, model.isLive)) model.session.startScan()
    if (!model.session.radioOn.value) onBluetoothOff()
}
