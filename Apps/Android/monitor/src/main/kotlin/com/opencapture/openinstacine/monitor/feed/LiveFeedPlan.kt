package com.opencapture.openinstacine.monitor.feed

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.opencine.cameracontrols.rememberMonitorFeedEffectsPlans
import com.opencapture.opencine.appkitnative.MonitorLiveFeedIntegration
import com.opencapture.opencine.cameracontrols.rememberMonitorFeedEffectsPlan
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.runtime.GlesPresentationOptions
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.lut.appLutLibrary
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.session.LunaCameraLUTProfile

/** The shared native feeds on the Luna clip ceiling, this app's crash guard, journal and upscaler. */
internal val LiveFeed = MonitorLiveFeedIntegration(LunaScopeExposureCeiling.PROFILE, appVulkanCrashGuard,
    DiagnosticCenter::log, { GlesPresentationOptions(OperatorPrefs.feedUpscaler(it)) })

/** The live, playback or inspector plan through the Luna camera looks. */
@Composable
internal fun rememberLiveFeedEffectsPlan(
    assist: MonitorAssistState,
    lutSelection: String,
    status: CameraStatus,
    family: String,
    cameraName: String?,
    playback: Boolean = false,
    clipColorMode: Int = -1,
    previewTool: MonitorAssistTool? = null,
): FeedEffectsRenderPlan {
    val plans = rememberMonitorFeedEffectsPlans(SwiftCore)
    val customLutGeneration by appLutLibrary(LocalContext.current).renderGeneration.collectAsState()
    return rememberMonitorFeedEffectsPlan(plans, OperatorPrefs, assist, lutSelection, status,
        LunaCameraLUTProfile.value, playback, clipColorMode, previewTool,
        customLutGeneration = customLutGeneration)
}
