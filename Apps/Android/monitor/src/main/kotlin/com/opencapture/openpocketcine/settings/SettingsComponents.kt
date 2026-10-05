package com.opencapture.openpocketcine.settings

import com.opencapture.openpocketcine.feed.fromColorMode

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.opencapture.monitorui.LocalMonitorInspectorHelp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import com.opencapture.openpocketcine.assists.FalseColorReference
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeExposureCeiling
import com.opencapture.opencine.media.ScopeClipSource
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.roundToInt
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

/**
 * A card whose rows are divider-separated with no per-row borders (iOS
 * `SettingsRowCard`). Optional [title] / [onReset] match the assist-tool cards
 * on Operator Setup → View Assist.
 */
@Composable
fun SettingsRowCard(
    title: String? = null,
    onReset: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    com.opencapture.monitorui.settings.MonitorSettingsRowCard(title = title, onReset = onReset, content = content)
}

/**
 * Accent capsule action used on Link / System trailing controls (iOS
 * `SettingsActionPill`). Title is uppercased to match the iOS monospaced pill.
 */
@Composable
fun SettingsActionPill(title: String, icon: OpcIcon? = null, tint: Color = LiveDesign.accent,
    background: Color = LiveDesign.accentDim, modifier: Modifier = Modifier,
    enabled: Boolean = true, onClick: () -> Unit) {
    com.opencapture.monitorui.settings.MonitorSettingsActionPill(
        title, icon, tint, background, modifier, enabled, onClick = onClick)
}

/**
 * Link Health dash-scale meter (iOS `SettingsDashScale`): POOR / WATCH / STABLE
 * marker over a 12-dash track with a three-band legend.
 */
/**
 * One label-plus-trailing-control row for a divider-separated card
 * (iOS `SettingsInlineRow`). When [stacked] is true (two-column View Assist
 * cards), the control sits under the title at full width.
 *
 * [help] renders the same "?" badge iOS puts beside the title - the copy that
 * explains what a control actually does lives there, not in a caption, so the
 * row stays one line until an operator asks.
 */
@Composable
fun SettingsInlineRow(
    title: String,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    trailing: @Composable () -> Unit,
) {
    com.opencapture.monitorui.settings.MonitorSettingsInlineRow(title = title, help = help, showTopDivider = showTopDivider, stacked = stacked, trailing = trailing)
}

/** Switch row inside a row card (iOS `SettingsSwitchInlineRow`). */
@Composable
fun SettingsSwitchRow(
    title: String,
    isOn: Boolean,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    testTag: String? = null,
    onToggle: () -> Unit,
) {
    com.opencapture.monitorui.settings.MonitorSettingsSwitchInlineRow(title = title, isOn = isOn, help = help, showTopDivider = showTopDivider, stacked = stacked, testTag = testTag, onToggle = onToggle)
}

/** iOS `SettingsSwitchInlineRow` - Pocket call-site alias of [SettingsSwitchRow]. */
@Composable
fun SettingsSwitchInlineRow(
    title: String,
    isOn: Boolean,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    testTag: String? = null,
    onToggle: () -> Unit,
) {
    SettingsSwitchRow(
        title = title,
        isOn = isOn,
        help = help,
        showTopDivider = showTopDivider,
        stacked = stacked,
        testTag = testTag,
        onToggle = onToggle,
    )
}

/**
 * iOS `SettingsSegmented`: pill track with equal or intrinsic segments. Active
 * segment uses surface fill + primary text (not accent chips).
 */
@Composable
fun SettingsSegmented(
    options: List<String>,
    selected: String,
    compact: Boolean = true,
    fillWidth: Boolean = compact,
    accentSelection: Boolean = false,
    testTag: String? = null,
    onSelect: (String) -> Unit,
) =
    com.opencapture.monitorui.settings.MonitorSettingsSegmented(options, selected, compact, fillWidth, accentSelection, testTag, onSelect)

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

/** iOS `SettingsSwitchGraphic`: 39×22 capsule, cyan thumb on dim track when on. */
@Composable
fun SettingsSwitchGraphic(isOn: Boolean) {
    com.opencapture.monitorui.settings.MonitorSettingsSwitchGraphic(isOn = isOn)
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
