package com.opencapture.openinstacine.monitor.feed

import androidx.compose.runtime.Composable
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.opencine.cameracontrols.MonitorFeedEffectsPlans
import com.opencapture.opencine.appkitnative.MonitorLiveFeedIntegration
import com.opencapture.opencine.cameracontrols.rememberMonitorFeedEffectsPlan
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.runtime.GlesPresentationOptions
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.session.LunaCameraLUTProfile

/** The shared native feeds on the Luna clip ceiling, this app's crash guard, journal and upscaler. */
internal val LiveFeed = MonitorLiveFeedIntegration(LunaScopeExposureCeiling.PROFILE, appVulkanCrashGuard,
    DiagnosticCenter::log, { GlesPresentationOptions(OperatorPrefs.feedUpscaler(it)) })

/** The shared feed plans on this app's Swift core bakes; one cube cache for the process. */
internal val FeedEffectsPlans = MonitorFeedEffectsPlans(SwiftCore)

/** The live, playback or inspector plan through the Luna camera looks. */
@Composable
internal fun rememberLiveFeedEffectsPlan(
    assist: MonitorAssistState,
    lutSelection: String,
    status: CameraStatus,
    playback: Boolean = false,
    clipColorMode: Int = -1,
    previewTool: MonitorAssistTool? = null,
): FeedEffectsRenderPlan =
    rememberMonitorFeedEffectsPlan(FeedEffectsPlans, OperatorPrefs, assist, lutSelection, status,
        LunaCameraLUTProfile.value, playback, clipColorMode, previewTool)
