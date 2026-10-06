package com.opencapture.openpocketcine.media

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import com.opencapture.openpocketcine.GlassTier
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.liveChromeGlass
import com.opencapture.openpocketcine.panelGlass

val MediaCapsuleShape: RoundedCornerShape = RoundedCornerShape(percent = 50)

val MediaCornerShape: RoundedCornerShape = ChromeShape

@Composable
fun Modifier.mediaGlass(shape: Shape = MediaCornerShape): Modifier {
    val glass = LocalMonitorGlass.current
    return if (glass == null) panelGlass(shape) else liveChromeGlass(shape)
}

fun Modifier.mediaSheetPlate(shape: Shape = MediaCornerShape): Modifier =
    background(LiveDesign.sheetPlate, shape).border(1.dp, LiveDesign.hairlineStrong, shape)

@Composable
fun MediaCloseButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 37.dp,
    enabled: Boolean = true,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .mediaGlass(CircleShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            icon = OpcIcon.X,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(size * 0.30f),
        )
    }
}

@Composable
fun MediaCircleIconButton(
    icon: OpcIcon,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
    iconSize: Dp = size * 0.47f,
    tint: androidx.compose.ui.graphics.Color = LiveDesign.text,
    enabled: Boolean = true,
    highlighted: Boolean = false,
    filled: Boolean = false,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .then(if (highlighted) Modifier.background(LiveDesign.accentDim, CircleShape) else Modifier)
            .mediaGlass(CircleShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            icon = icon,
            contentDescription = null,
            tint = if (!enabled) LiveDesign.faint else if (highlighted) LiveDesign.accent else tint,
            modifier = Modifier.size(iconSize),
            filled = filled,
        )
    }
}

@Composable
fun MediaGlassTrack(
    fraction: Float,
    modifier: Modifier = Modifier,
    trackWidth: Dp? = null,
    trackHeight: Dp = 4.dp,
) {
    com.opencapture.monitorui.MonitorMediaProgressTrack(fraction, modifier, trackWidth, trackHeight)
}

internal object PlaybackChromeMetrics {
    val transportButtonWidth = 38.dp
    val transportButtonHeight = 36.dp
    val actionButtonWidth = 32.dp
    val actionButtonHeight = 36.dp
    val transportIconSize = 18.dp
    val primaryTransportIconSize = 22.dp
    val actionIconSize = 16.dp
    val corner = MediaCornerShape
    const val barPaddingH = 10f
    const val transportRowSpacing = 5f
    const val narrowestScreenWidth = 375f
    const val chromeHorizontalPadding = 16f
    const val topScrimDp = 120f
    const val bottomScrimDp = 200f
    const val SAMPLE_MS = 80L
    const val SAMPLE_MAX_SIDE = 480f
    const val actionChipSize = 44f
    const val actionChipIcon = 18f
    const val actionChipCorner = 14f
    val hideChromeIcon = OpcIcon.MAXIMIZE
    val showChromeIcon = OpcIcon.MINIMIZE

    fun usesDarkenedBars(tier: GlassTier): Boolean = tier == GlassTier.FLAT

    /** iOS `MediaPlayerView.PlaybackChrome.transportRowWidth`. */
    fun transportRowWidth(
        transportCount: Int = 3,
        actionCount: Int = 5,
        minimumSpacer: Float = 6f,
    ): Float {
        val buttons = 38f * transportCount + 32f * actionCount
        val gaps = transportRowSpacing * (transportCount + actionCount - 1)
        return buttons + gaps + barPaddingH * 2 + minimumSpacer
    }
}

