package com.opencapture.openinstacine.monitor.assists

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.cameracontrols.AssistHost
import com.opencapture.opencine.cameracontrols.AssistLutPicker
import com.opencapture.opencine.cameracontrols.AssistOptionsPanel
import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.lut.AppLutPickerCopy
import com.opencapture.openinstacine.monitor.settings.SettingsPalette
import com.opencapture.monitorui.MonitorAssistTool

/** This app's assist values: its settings palettes and ND copy; the live ceiling and the union guide mask. */
internal val AppAssistHost = AssistHost(
    peakingColors = SettingsPalette.peaking,
    highlightColors = SettingsPalette.highlight,
    midtoneColors = SettingsPalette.midtone,
    ndHelp = ND_HELP,
)

/** This app's ND help copy, as on its main (the shared [com.opencapture.opencine.cameracontrols.NDAssist.HELP] uses hyphens). */
private const val ND_HELP =
    "Meters the live picture against middle gray and suggests a screw-on ND \u2014 stops and ND number \u2014 to balance it. The app cannot set a filter."

/**
 * OpenZCine / iOS long-press tray: camera-controls' [AssistOptionsPanel] with this app's values.
 *
 * [model] owns the live LUT selection. When omitted (current live-view call
 * site), the picker writes [OperatorPrefs] so a later process still restores.
 */
@Composable
fun AssistOptionsPopup(
    tool: MonitorAssistTool,
    state: LiveAssistState,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    model: AppModel? = null,
    maxHeightDp: Float? = null,
    colorMode: Int = CameraCommands.COLOR_NORMAL,
    embedded: Boolean = false,
    playback: Boolean = false,
    isPhoto: Boolean = false,
) {
    val context = LocalContext.current
    var fallbackLut by remember {
        mutableStateOf(model?.lutSelection ?: OperatorPrefs.lutSelection(context))
    }
    val lutSelection = model?.lutSelection ?: fallbackLut
    val lut = AssistLutPicker(
        copy = AppLutPickerCopy,
        selection = lutSelection,
        onSelect = { id ->
            if (model != null) {
                model.updateLutSelection(id)
            } else {
                fallbackLut = id
                OperatorPrefs.setLutSelection(context, id)
            }
        },
        family = model?.session?.connectedCamera?.model?.family ?: "pocket",
        cameraName = model?.session?.connectedCamera?.name,
        colorMode = colorMode,
    )
    AssistOptionsPanel(
        tool, state, onDismiss, AppAssistHost, lut, modifier, maxHeightDp, MonitorTransfer.fromColorMode(colorMode), embedded, playback, isPhoto,
        imagePreview = model?.let { { AssistInspectorImagePreview(tool, state, it, lutSelection, colorMode, playback) } },
    )
}
