package com.opencapture.openinstacine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.opencapture.opencine.cameracontrols.OperatorAppInformation
import com.opencapture.opencine.cameracontrols.OperatorDiagnostics
import com.opencapture.opencine.cameracontrols.OperatorHelpCopy
import com.opencapture.opencine.cameracontrols.OperatorLinkSample
import com.opencapture.opencine.cameracontrols.OperatorSetupApp
import com.opencapture.opencine.cameracontrols.OperatorSetupState
import com.opencapture.opencine.cameracontrols.formatAppVersion
import com.opencapture.opencine.cameracontrols.monitorSettingsCacheSource
import com.opencapture.opencine.runtime.MonitorGlesUpscaler
import com.opencapture.openinstacine.monitor.assists.AppAssistHost
import com.opencapture.openinstacine.monitor.diagnostics.AppDiagnostics
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.lut.LUTPicker
import com.opencapture.openinstacine.monitor.session.vocabularyPhase
import com.opencapture.openinstacine.monitor.settings.PanelCloseButton

object SettingsHelpCopy : OperatorHelpCopy("OpenInstaCine")

object OpenPocketCineLinks {
    const val SOURCE = "https://github.com/erik-sutton95/OpenInstaCine"
    const val SUPPORT = "https://github.com/erik-sutton95/OpenInstaCine/discussions/categories/q-a"
    const val REPORT_PROBLEM =
        "https://github.com/erik-sutton95/OpenInstaCine/issues/new?template=bug_report.yml"
    const val FEATURE_REQUEST =
        "https://github.com/erik-sutton95/OpenInstaCine/discussions/new?category=ideas"
    const val PRIVACY = "https://opencapture.org/openinstacine/privacy"
    const val TERMS = "https://opencapture.org/openinstacine/terms"
}

/** The link and body Operator Setup shows, from this app's session. */
@Composable
internal fun AppModel.operatorSetupState(): OperatorSetupState {
    val phase by session.phaseFlow.collectAsState()
    val failure by session.failure.collectAsState()
    val status by session.chromeStatus.collectAsState()
    val camera = session.connectedCamera
    val shown by shell.state.collectAsState()
    return OperatorSetupState(phase.vocabularyPhase(), failure, status.monitorColorMode, session.joinedSSID, camera?.name,
        camera?.model?.family, remember(status) { monitorLayout() },
        lookProfile = camera?.model?.captureProfile?.looks ?: com.opencapture.openinstacine.monitor.session.LunaCameraLUTProfile.value,
        monitorPresented = shown.monitor != null)
}

/**
 * Insta's copy, links, stores and pages, as on main; App Information uses iPhone main's Insta360 wording
 * (Android main showed Pocket's DJI copy, a kept fix).
 */
internal fun operatorSetupApp(model: AppModel) = OperatorSetupApp(
    wordmark = MonitorConfiguration.identity.wordmark,
    help = SettingsHelpCopy,
    prefs = OperatorPrefs,
    assistHost = AppAssistHost,
    upscalers = MonitorGlesUpscaler.supported.map { it.label },
    upscaler = { OperatorPrefs.feedUpscaler(it).label },
    setUpscaler = { context, label -> OperatorPrefs.setFeedUpscaler(context, MonitorGlesUpscaler.fromStored(label)) },
    linkSample = {
        val session = model.session
        OperatorLinkSample(session.decoder.framesEnqueued.get(), session.decoder.lastPresentedAt,
            session.videoPackets, session.hasVideoFormat)
    },
    information = OperatorAppInformation(
        theme = "Charcoal",
        themeHelp = "Charcoal field-monitor chrome with yellow accents, tuned for low reflection on set.",
        protocol = "Insta360 / BLE + Wi-Fi",
        protocolHelp = "Camera control speaks Insta360's protocol over Bluetooth and the camera's Wi-Fi. No Insta360 SDK is bundled or required.",
        version = formatAppVersion(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toLong()),
        versionHelp = SettingsHelpCopy.APP_VERSION, termsHelp = "How you can use OpenInstaCine.",
    ),
    sourceUrl = OpenPocketCineLinks.SOURCE,
    diagnostics = OperatorDiagnostics(
        AppDiagnostics.reporting, AppDiagnostics.manualReport, AppDiagnostics.incidents,
        diagnosticText = { DiagnosticCenter.boundedDiagnosticText(model.session) },
        shareReport = { DiagnosticCenter.shareReport(it, model.session, copyForFeedback = false) },
    ),
    reportProblem = { model.problemReportOpen = true },
    legal = InstaLegalDocuments,
    lutPicker = { onClose -> LUTPicker(model = model, onClose = onClose) },
    // Every camera bucket, retaining the current gallery's operation fencing and revision.
    cacheSource = { monitorSettingsCacheSource(model.mediaLibrary, model.mediaStorage, model.mediaCacheParent) },
)

@Composable
fun OperatorSetupScreen(model: AppModel, onClose: () -> Unit) {
    CompositionLocalProvider(LocalMonitorGlass provides null) {
        com.opencapture.opencine.cameracontrols.OperatorSetupScreen(
            model, model.operatorSetupState(), remember(model) { operatorSetupApp(model) }, onClose)
    }
}

@Composable
fun OperatorCloseButton(onClose: () -> Unit, modifier: Modifier = Modifier) {
    PanelCloseButton(onClick = onClose, modifier = modifier)
}
