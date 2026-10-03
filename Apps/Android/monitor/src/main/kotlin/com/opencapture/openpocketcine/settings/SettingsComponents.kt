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
import com.opencapture.monitorui.MonitorLinkHealth
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.roundToInt

private fun chromeStyle(size: Float, weight: FontWeight, mono: Boolean = false): TextStyle =
    if (mono) LiveType.mono(size, weight) else LiveType.ui(size, weight)

/** iOS `monitorCardSurface`: solid Field Monitor card with a hairline border. */
private fun Modifier.settingsCardSurface(): Modifier =
    background(LiveDesign.surface, ChromeShape).border(1.dp, LiveDesign.hairline, ChromeShape)

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

/** Circular refresh-cw reset control (iOS `SettingsResetButton`, 28dp). */
@Composable
fun SettingsResetButton(onClick: () -> Unit) {
    com.opencapture.monitorui.settings.MonitorSettingsResetButton(onClick = onClick)
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
        title, icon, tint, background, modifier, enabled, onClick)
}

/**
 * Link Health dash-scale meter (iOS `SettingsDashScale`): POOR / WATCH / STABLE
 * marker over a 12-dash track with a three-band legend.
 */
@Composable
fun SettingsDashScale(title: String, caption: String, score: Int) {
    val band = MonitorLinkHealth.band(score)
    val bandColor = MonitorLinkHealth.color(score)
    val litCount =
        when (band) {
            MonitorLinkHealth.Band.POOR -> 4
            MonitorLinkHealth.Band.WATCH -> 8
            MonitorLinkHealth.Band.STABLE -> 12
        }
    val bandSlot =
        when (band) {
            MonitorLinkHealth.Band.POOR -> 0
            MonitorLinkHealth.Band.WATCH -> 1
            MonitorLinkHealth.Band.STABLE -> 2
        }
    val bandLabel =
        when (band) {
            MonitorLinkHealth.Band.POOR -> "POOR"
            MonitorLinkHealth.Band.WATCH -> "WATCH"
            MonitorLinkHealth.Band.STABLE -> "STABLE"
        }
    Column(
        Modifier.fillMaxWidth()
            .settingsCardSurface()
            .padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Text(title, style = chromeStyle(13f, FontWeight.SemiBold), color = LiveDesign.text)
        Text(
            caption,
            style = chromeStyle(11.5f, FontWeight.Medium, mono = true),
            color = LiveDesign.muted,
        )
        Row(Modifier.fillMaxWidth().height(19.dp)) {
            repeat(3) { slot ->
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    if (slot == bandSlot) {
                        Text(
                            bandLabel,
                            style = chromeStyle(9.5f, FontWeight.Bold, mono = true),
                            color = bandColor,
                            letterSpacing = 0.5.sp,
                            modifier =
                                Modifier
                                    .background(bandColor.copy(alpha = 0.12f), CircleShape)
                                    .border(1.dp, bandColor, CircleShape)
                                    .padding(horizontal = 10.dp, vertical = 4.dp),
                        )
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            repeat(12) { index ->
                val fill =
                    when {
                        index >= litCount -> LiveDesign.hairlineStrong
                        index < 4 -> MonitorLinkHealth.poor.copy(alpha = 0.8f)
                        index < 8 -> MonitorLinkHealth.watch.copy(alpha = 0.85f)
                        else -> MonitorLinkHealth.stable.copy(alpha = 0.9f)
                    }
                Box(
                    Modifier.weight(1f)
                        .height(6.dp)
                        .background(fill, CircleShape),
                )
            }
        }
        Row(Modifier.fillMaxWidth()) {
            DashLegend("Poor", "<50", Modifier.weight(1f), Alignment.Start)
            DashLegend("Watch", "50-79", Modifier.weight(1f), Alignment.CenterHorizontally)
            DashLegend("Stable", "80+", Modifier.weight(1f), Alignment.End)
        }
    }
}

@Composable
private fun DashLegend(
    name: String,
    sub: String,
    modifier: Modifier,
    alignment: Alignment.Horizontal,
) {
    Row(
        modifier,
        horizontalArrangement =
            when (alignment) {
                Alignment.Start -> Arrangement.Start
                Alignment.End -> Arrangement.End
                else -> Arrangement.Center
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, style = chromeStyle(10f, FontWeight.SemiBold), color = LiveDesign.muted)
        Spacer(Modifier.size(4.dp))
        Text(sub, style = chromeStyle(9f, FontWeight.Normal, mono = true), color = LiveDesign.faint)
    }
}

/**
 * One label-plus-trailing-control row for a divider-separated card
 * (iOS `SettingsInlineRow`). When [stacked] is true (two-column View Assist
 * cards), the control sits under the title at full width.
 *
 * [help] renders the same "?" badge iOS puts beside the title — the copy that
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

/** iOS `SettingsSwitchInlineRow` — Pocket call-site alias of [SettingsSwitchRow]. */
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
 * iOS `HelpBadge`: a quiet "?" beside a row title that reveals the row's help
 * copy in a glass popover.
 *
 * ponytail: a transcription of the private badge in media/PlaybackAssistOptions.kt
 * (the assist popups own theirs) — settings cannot see it. Hoist one copy if a
 * third surface ever needs it.
 */
@Composable
fun SettingsHelpBadge(text: String) {
    com.opencapture.monitorui.settings.MonitorSettingsHelpBadge(text = text)
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

/**
 * iOS `SettingsColorDots`: real colour circles (not text labels), selected with
 * a matching stroke ring.
 */
@Composable
fun SettingsColorDots(
    dots: List<SettingsColorDot>,
    selectedName: String,
    compact: Boolean = true,
    enabled: Boolean = true,
    onSelect: (String) -> Unit,
) =
    com.opencapture.monitorui.settings.MonitorSettingsColorDots(dots, selectedName, compact, enabled, onSelect)

/** One named swatch for [SettingsColorDots] (iOS `SettingsColorDots.Dot`). */
typealias SettingsColorDot = com.opencapture.monitorui.settings.MonitorSettingsColorDot

/** iOS `SettingsPalette` — zone-scoped stripe/peaking colours. */
object SettingsPalette {
    val highlight: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("White", LiveDesign.text),
            SettingsColorDot("Amber", LiveDesign.accent),
            SettingsColorDot("Red", LiveDesign.rec),
        )
    val midtone: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("Amber", LiveDesign.accent),
            SettingsColorDot("Cyan", LiveDesign.info),
            SettingsColorDot("Green", LiveDesign.good),
        )
    val peaking: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("White", LiveDesign.text),
            SettingsColorDot("Blue", LiveDesign.info),
            SettingsColorDot("Red", LiveDesign.rec),
            SettingsColorDot("Green", LiveDesign.good),
        )
}

/**
 * iOS `SettingsNumberField`: compact mono value field with digit pad and clamp.
 * Done on the IME commits and hides the pad. Bring-into-view so Operator Setup
 * on a small phone still reveals Highlight / Midtone.
 */
@Composable
fun SettingsNumberField(value: Int, maximum: Int, onChange: (Int) -> Unit) {
    com.opencapture.monitorui.settings.MonitorSettingsNumberField(value, maximum, onChange)
}

/** Compact native slider with the existing trailing numeric readout. */
@Composable
fun SettingsPercentSlider(
    value: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
) =
    com.opencapture.monitorui.settings.MonitorSettingsPercentSlider(value, range, onChange)

/** Thin accent track + white thumb, matching iOS `Slider` in Operator Setup. */
@Composable
fun SettingsValueSlider(
    value: Int,
    range: IntRange,
    label: String,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    labelWidth: Int = 40,
) =
    com.opencapture.monitorui.settings.MonitorSettingsValueSlider(value, range, label, onChange, modifier, labelWidth)

/** Existing assist values adapt to a compact iOS-like track rather than the 44dp drum slider. */
@Composable
fun GlassPillSlider(value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier) =
    com.opencapture.monitorui.settings.MonitorSettingsPillSlider(value, range, onChange, modifier)

/**
 * iOS `SettingsCrushClipSegmented`: five equal stop segments with fraction
 * glyphs (0 · ¼ · ½ · ¾ · 1).
 */
@Composable
fun SettingsCrushClipSegmented(
    options: List<Pair<String, String>>,
    selectedLabel: String,
    accentSelection: Boolean = false,
    onSelect: (String) -> Unit,
) =
    com.opencapture.monitorui.settings.MonitorSettingsCrushClipSegmented(options, selectedLabel, accentSelection, onSelect)

/** iOS `SettingsSwitchGraphic`: 39×22 capsule, cyan thumb on dim track when on. */
@Composable
fun SettingsSwitchGraphic(isOn: Boolean) {
    com.opencapture.monitorui.settings.MonitorSettingsSwitchGraphic(isOn = isOn)
}

/** Plain monospace value text (iOS `SettingsValueText`). */
@Composable
fun SettingsValueText(value: String) {
    com.opencapture.monitorui.settings.MonitorSettingsValueText(value = value)
}

/** Accent inline action ("Open", "Sign in") — the iOS System-tab link button treatment. */
@Composable
fun SettingsLinkAction(
    title: String,
    contentDescription: String = title,
    onClick: () -> Unit,
): Unit {
    Box(
        Modifier.defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .semantics { this.contentDescription = contentDescription }
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = chromeStyle(13f, FontWeight.SemiBold),
            color = LiveDesign.accent,
        )
    }
}

/**
 * Quiet utility text link — mirrors the startup header's Privacy/Terms
 * treatment (iOS `StartupHeader.legalLink`): deliberately dimmer than row
 * titles so it never competes with them.
 */
@Composable
fun SettingsQuietLink(title: String, onClick: () -> Unit): Unit {
    Box(
        Modifier.defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = LiveDesign.faint,
            maxLines = 1,
        )
    }
}

/**
 * Titled glass card with an optional per-tool reset and free-form content.
 *
 * [captionMaxLines] defaults to the compact settings-card treatment. Flows
 * that communicate a consequential choice can opt into an unbounded caption
 * so accessibility font scaling never hides that context.
 */
@Composable
fun SettingsGroupCard(title: String, caption: String, onReset: (() -> Unit)? = null,
    captionMaxLines: Int = 2, expanded: Boolean? = null, onExpandToggle: (() -> Unit)? = null,
    content: @Composable () -> Unit) {
    com.opencapture.monitorui.settings.MonitorSettingsGroupCard(
        title, caption, onReset, captionMaxLines, expanded, onExpandToggle, content)
}

/** Small label + switch tile for toggle grids (iOS `DisplayToggleItem`). */
@Composable
fun DisplayToggleItem(title: String, isOn: Boolean, modifier: Modifier = Modifier, onToggle: () -> Unit) {
    com.opencapture.monitorui.settings.MonitorSettingsDisplayToggle(title, isOn, modifier, onToggle)
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

/** Compact settings key; uses the same transfer-aware bands as the live reference. */
@Composable
fun SettingsFalseColorKey(
    scale: FalseColorScale,
    colorMode: Int,
    ceiling: ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
) {
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val segments = FalseColorReference.segments(scale, transfer, ceiling = ceiling)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Canvas(Modifier.fillMaxWidth().height(11.dp)) {
            drawRect(Color.White.copy(alpha = 0.5f))
            segments.forEach { segment ->
                val lo = segment.lowerFraction.toFloat()
                val hi = segment.upperFraction.toFloat()
                drawRect(
                    Color(segment.band.red.toFloat(), segment.band.green.toFloat(), segment.band.blue.toFloat()),
                    Offset(size.width * lo, 0f),
                    Size(maxOf(1f, size.width * (hi - lo)), size.height),
                )
            }
        }
        if (scale.usesSceneStops) {
            BoxWithConstraints(Modifier.fillMaxWidth().height(12.dp)) {
                val rulerWidth = maxWidth
                FalseColorReference.sceneStopMarkers(transfer, ceiling = ceiling).forEach { marker ->
                    Text(marker.label, style = LiveType.mono(7f), color = LiveDesign.muted,
                        modifier = Modifier.offset(x = (rulerWidth * marker.fraction.toFloat() - 8.dp)
                            .coerceIn(0.dp, (rulerWidth - 16.dp).coerceAtLeast(0.dp))))
                }
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                FalseColorReference.axisLabels(scale).forEach { label ->
                    Text(label, style = LiveType.ui(7f), color = LiveDesign.muted)
                }
            }
        }
    }
}
