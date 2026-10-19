package com.opencapture.openinstacine.monitor.assists

import com.opencapture.monitorui.MonitorGuideMaskPolicy
import com.opencapture.opencine.cameracontrols.AssistHost
import com.opencapture.openinstacine.monitor.settings.SettingsPalette

/**
 * This app's assist values: its settings palettes and ND copy, and the envelope guide mask its
 * baseline and Pocket keep (IA-251: the space between crossing frames stays clear).
 */
internal val AppAssistHost = AssistHost(
    peakingColors = SettingsPalette.peaking,
    highlightColors = SettingsPalette.highlight,
    midtoneColors = SettingsPalette.midtone,
    ndHelp = ND_HELP,
    guideMaskPolicy = MonitorGuideMaskPolicy.ENVELOPE,
    rec709LookCurve = { com.opencapture.openinstacine.monitor.feed.LunaMonitorColorProfile.value.rec709LookCurves[it] },
)

/** This app's ND help copy, as on its main (the shared [com.opencapture.opencine.cameracontrols.NDAssist.HELP] uses hyphens). */
private const val ND_HELP =
    "Meters the live picture against middle gray and suggests a screw-on ND \u2014 stops and ND number \u2014 to balance it. The app cannot set a filter."
