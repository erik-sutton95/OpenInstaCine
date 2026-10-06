package com.opencapture.openinstacine.monitor.lut

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.cameracontrols.LUTPicker
import com.opencapture.opencine.cameracontrols.LutPickerCopy
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.openinstacine.monitor.AppModel

/** What this app's LUT picker says: the camera looks sit on the Camera tab with the shared Auto. */
internal val AppLutPickerCopy = LutPickerCopy(
    cameraTab = "Camera",
    autoId = LutCatalog.AUTO,
    customHint = "Imported looks land here. Auto keeps the Rec.709 preview unchanged.",
    noLookCaption = "Rec.709 preview · no conversion needed",
    officialCubeCaption = "Camera looks for this color profile",
    cameraLooksCaption = "Camera looks for this color profile",
)

/** Settings sheet. Same body as the assist-tray form; 50/50 stays inline. */
@Composable
fun LUTPicker(model: AppModel, onClose: () -> Unit) {
    val assist = model.assist
    val status by model.session.chromeStatus.collectAsState()
    LUTPicker(
        copy = AppLutPickerCopy,
        selection = model.lutSelection,
        onSelect = model::updateLutSelection,
        onClose = onClose,
        embedded = false,
        splitComparison = assist.splitComparison,
        splitVertical = assist.splitVertical,
        lutExposureStops = assist.lutExposureStops,
        onToggleSplit = { assist.setSplitComparison(!assist.splitComparison) },
        onSplitVertical = { assist.setSplitComparison(assist.splitComparison, it) },
        onExposure = { assist.updateLutExposure(it) },
        onArmLut = { assist.armLut() },
        colorMode = status.monitorColorMode,
        family = model.session.connectedCamera?.model?.family ?: "pocket",
        cameraName = model.session.connectedCamera?.name,
        isPhoto = status.isPhoto,
    )
}
