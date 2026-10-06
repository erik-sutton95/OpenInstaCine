package com.opencapture.openpocketcine.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.panelGlass
import com.opencapture.monitorui.settings.MonitorSettingsColorDot

// Compose ports of the iOS operator-settings primitives (SettingsRootView /
// AppSettings: SettingsRowCard, SettingsInlineRow, SettingsSwitchInlineRow,
// SettingsSwitchGraphic, SettingsValueText, SettingsGroupCard,
// DisplayToggleItem, CloseButton, HelpBadge). Same metrics as OpenZCine
// Android; Pocket tokens stay DJI-black / cyan.

/** Ripple-free click carrying a semantics [role] (the settings-panel `chromeClickable`). */
@Composable
internal fun Modifier.settingsClickable(role: Role, enabled: Boolean = true, onClick: () -> Unit): Modifier =
    clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        enabled = enabled,
        role = role,
        onClick = onClick,
    )

/** iOS `SettingsPalette` - zone-scoped stripe/peaking colours. */
object SettingsPalette {
    val highlight: List<MonitorSettingsColorDot> =
        listOf(
            MonitorSettingsColorDot("White", LiveDesign.text),
            MonitorSettingsColorDot("Amber", LiveDesign.accent),
            MonitorSettingsColorDot("Red", LiveDesign.rec),
        )
    val midtone: List<MonitorSettingsColorDot> =
        listOf(
            MonitorSettingsColorDot("Amber", LiveDesign.accent),
            MonitorSettingsColorDot("Cyan", LiveDesign.info),
            MonitorSettingsColorDot("Green", LiveDesign.good),
        )
    val peaking: List<MonitorSettingsColorDot> =
        listOf(
            MonitorSettingsColorDot("White", LiveDesign.text),
            MonitorSettingsColorDot("Blue", LiveDesign.info),
            MonitorSettingsColorDot("Red", LiveDesign.rec),
            MonitorSettingsColorDot("Green", LiveDesign.good),
        )
}

/** Floating xmark close button on a glass circle (iOS `CloseButton`, 37pt). */
@Composable
fun PanelCloseButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(37.dp)
            .panelGlass(CircleShape)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            icon = OpcIcon.X,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(13.dp),
        )
    }
}
