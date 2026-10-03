package com.opencapture.openpocketcine.assists

/**
 * OpenZCine cinema live-monitor set. Pocket omits MAG, PLAY.
 *
 * Toolbar: LUT PEAK FALSE | ZEBRA WAVE PARADE | HISTO VECTOR LIGHTS ND EV |
 * GUIDES GRID CROSS LEVEL DE-SQ | MIRROR | AUDIO.
 */
enum class LiveAssistTool {
    LUT,
    PEAK,
    FALSE,
    ZEBRA,
    WAVE,
    PARADE,
    HISTO,
    VECTOR,
    LIGHTS,
    ND,
    EV,
    AUDIO,
    GUIDES,
    GRID,
    CROSS,
    LEVEL,
    DESQ,
    MIRROR,
    ;

    val chipLabel: String
        get() = if (this == DESQ) "DE-SQ" else name

    val label: String
        get() = name

    val title: String
        get() =
            when (this) {
                LUT -> "LUT"
                PEAK -> "Peaking"
                FALSE -> "False Color"
                ZEBRA -> "Zebra"
                WAVE -> "Waveform"
                PARADE -> "RGB Parade"
                HISTO -> "Histogram"
                VECTOR -> "Vectorscope"
                LIGHTS -> "Traffic Lights"
                ND -> "ND Suggestion"
                EV -> "EV Meter"
                AUDIO -> "Audio Levels"
                GUIDES -> "Guides"
                GRID -> "Grid"
                CROSS -> "Crosshair"
                LEVEL -> "Level"
                DESQ -> "Anamorphic Desqueeze"
                MIRROR -> "Mirror"
            }

    /** The fixed camera EV meter and LEVEL are tap-only toggles. */
    val hasConfiguration: Boolean
        get() =
            when (this) {
                EV, LEVEL -> false
                else -> true
            }

    companion object {
        val toolbarGroups: List<List<LiveAssistTool>> =
            listOf(
                listOf(LUT, PEAK, FALSE),
                listOf(ZEBRA, WAVE, PARADE),
                listOf(HISTO, VECTOR, LIGHTS, ND, EV),
                listOf(GUIDES, GRID, CROSS, LEVEL, DESQ),
                listOf(MIRROR),
            )

        /** AUDIO is appended as its own trailing section. */
        val toolbarCases: List<LiveAssistTool> = toolbarGroups.flatten()

        /** Camera EV and LEVEL have no clip telemetry; AUDIO rides last like live. */
        val playbackToolbarCases: List<LiveAssistTool> = toolbarCases.filter { it != EV && it != LEVEL } + AUDIO

        val settingsCases: List<LiveAssistTool> = toolbarCases + AUDIO

        val cleanPinCases: List<LiveAssistTool> = settingsCases.filter { it != EV }

        fun fromPersisted(raw: String): LiveAssistTool? =
            entries.firstOrNull { it.name == raw || it.chipLabel == raw }
    }
}

typealias GuideFamily = com.opencapture.monitorui.MonitorGuideFamily

typealias GuideAspect = com.opencapture.monitorui.MonitorGuideAspect

typealias PeakingColor = com.opencapture.opencine.media.MonitorPeakingColor

typealias PeakingSense = com.opencapture.opencine.media.MonitorPeakingSense

/**
 * [persisted] is the saved key. [STOPS] is the scale now labeled Video; its key stays
 * "CineStop" so saved settings keep the scale they chose. CineStop is [SCENE_STOPS].
 */
enum class FalseColorScale(val persisted: String, val menuLabel: String) {
    SCENE_STOPS("SceneStops", "CineStop"),
    STOPS("CineStop", "Video"),
    IRE("IRE", "IRE"),
    LIMITS("Limits", "Limits"),
    ;

    val usesSceneStops: Boolean get() = this == SCENE_STOPS

    companion object {
        fun fromPersisted(raw: String): FalseColorScale =
            entries.firstOrNull { it.persisted == raw || it.name == raw }
                ?: when (raw) {
                    "Stops", "ZC Stops", "PStops" -> STOPS
                    else -> SCENE_STOPS
                }

        fun fromMenuLabel(label: String): FalseColorScale =
            when (label) {
                "Video" -> STOPS
                "IRE" -> IRE
                "Limits" -> LIMITS
                else -> SCENE_STOPS
            }
    }
}

enum class ZebraUnit(val persisted: String, val editorLabel: String) {
    NATIVE("Native", "0-255"),
    IRE("IRE", "IRE"),
    ;

    companion object {
        fun fromPersisted(raw: String): ZebraUnit =
            entries.firstOrNull { it.persisted == raw || it.editorLabel == raw || it.name == raw }
                ?: IRE

        fun fromEditorLabel(label: String): ZebraUnit = if (label == "0-255") NATIVE else IRE
    }
}

typealias ZebraPaint = com.opencapture.opencine.media.MonitorZebraPaint

typealias WaveformMode = com.opencapture.monitorui.MonitorWaveformMode

typealias ParadeMode = com.opencapture.monitorui.MonitorParadeMode

typealias VectorscopeZoom = com.opencapture.monitorui.MonitorVectorscopeZoom

/** OpenZCine `AssistConfiguration.CrushClipCompensation` — shared HISTO + LIGHTS. */
typealias CrushClipCompensation = com.opencapture.opencine.media.MonitorCrushClipCompensation

object LiveZebra {
    const val HIGHLIGHT_IRE = 99.0
    const val MIDTONE_IRE = 55.0
    const val MIDTONE_HALF_WIDTH_IRE = 5.0
}
