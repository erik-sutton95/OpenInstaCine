package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.feed.fromColorMode

import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.monitorui.MonitorWaveformScopePlot
import com.opencapture.monitorui.MonitorParadeScopePlot
import com.opencapture.monitorui.MonitorVectorscopeScopePlot
import com.opencapture.monitorui.MonitorScopeGuides
import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.NDFilterRecommendation
import com.opencapture.openpocketcine.LocalOperatorHaptics

import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import com.opencapture.openpocketcine.feed.ScopeChannelLight
import com.opencapture.openpocketcine.feed.WaveformIre

private val PanelShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
private val ChipShape = RoundedCornerShape(percent = 50)
private val MeterRed = Color(255 / 255f, 92 / 255f, 82 / 255f)
private val MeterGreen = Color(86 / 255f, 235 / 255f, 132 / 255f)
private val MeterBlue = Color(96 / 255f, 158 / 255f, 255 / 255f)
private val MeterYellow = Color(245 / 255f, 208 / 255f, 82 / 255f)

@Composable
internal fun MovableAssistPanel(
    tool: LiveAssistTool, base: AssistSize, scale: Double, stored: StoredCenter?,
    canvas: AssistRect, placementBounds: AssistRect, defaultCenter: AssistPoint, enabled: Boolean,
    onStore: (StoredCenter) -> Unit, onScale: ((Double) -> Unit)? = null,
    onOpenOptions: ((ChromeRect) -> Unit)? = null, onActivate: () -> Unit = {},
    fillPlate: Boolean = true, chip: Boolean = false, content: @Composable (AssistSize) -> Unit,
) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorMovableScopePanel(
        identity = tool.name, base = base, scale = scale, stored = stored, canvas = canvas,
        placementBounds = placementBounds, defaultCenter = defaultCenter, enabled = enabled,
        onStore = onStore, onScale = onScale,
        onOpenOptions = onOpenOptions?.let { open -> { rect -> open(ChromeRect(rect.x, rect.y, rect.width, rect.height)) } },
        anchorOrigin = com.opencapture.openpocketcine.LocalLiveCanvasOrigin.current,
        onActivate = onActivate, onConfirm = { haptics.confirm() },
        fillPlate = fillPlate, chip = chip, content = content,
    )
}
@Composable
internal fun WaveformPanel(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val bundle = previewBundle ?: state.scopeBundle
    val transfer = bundle.resolvedTransfer(colorMode)
    val table = remember(transfer, bundle.iso, bundle.ceiling) { WaveformIre.levelTable(transfer, bundle.iso, bundle.ceiling) }
    MonitorWaveformScopePlot(bundle, transfer, table, state.waveMode,
        WaveformAssist.intensity(state.waveBrightness),
        MonitorScopeGuides(state.waveGuides.clip, state.waveGuides.crush, state.waveGuides.middle), modifier)
}

@Composable
internal fun ParadePanel(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val bundle = previewBundle ?: state.scopeBundle
    val transfer = bundle.resolvedTransfer(colorMode)
    val table = remember(transfer, bundle.iso, bundle.ceiling) { WaveformIre.levelTable(transfer, bundle.iso, bundle.ceiling) }
    MonitorParadeScopePlot(bundle, transfer, table, state.paradeMode,
        ParadeAssist.intensity(state.paradeBrightness),
        MonitorScopeGuides(state.paradeGuides.clip, state.paradeGuides.crush, state.paradeGuides.middle), modifier)
}

@Composable
internal fun HistogramPanel(state: LiveAssistState, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val bundle = previewBundle ?: state.scopeBundle
    com.opencapture.monitorui.MonitorHistogramScopePlot(bundle.histogramDisplay, bundle.traffic,
        state.histoTrafficLights, modifier)
}

@Composable
internal fun VectorscopePanel(state: LiveAssistState, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    MonitorVectorscopeScopePlot(previewBundle ?: state.scopeBundle, state.vectorZoom, state.vectorBrightness, modifier)
}

@Composable
internal fun TrafficLightsPanel(state: LiveAssistState, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val measurer = rememberTextMeasurer()
    val reading = (previewBundle ?: state.scopeBundle).traffic
    Canvas(modifier.fillMaxSize()) {
        val ui = minOf(this.size.width / ScopePanelSize.trafficLights.width, this.size.height / ScopePanelSize.trafficLights.height)
        val pad = TrafficLightsAssist.PANEL_PAD * ui
        drawText(
            measurer,
            TrafficLightsAssist.METER_TITLE,
            Offset(pad, pad),
            TextStyle(
                color = LiveDesign.text.copy(alpha = 0.58f),
                fontSize = 8.5.sp,
                fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
                fontWeight = FontWeight.Bold,
            ),
        )
        val colW = TrafficLightsAssist.TRACK_WIDTH * ui
        val colH = TrafficLightsAssist.COLUMN_HEIGHT * ui
        val gap = TrafficLightsAssist.COLUMN_SPACING * ui
        val startX = (this.size.width - (colW * 3 + gap * 2)) / 2f
        val top = pad + TrafficLightsAssist.TITLE_SIZE * ui + TrafficLightsAssist.TITLE_SPACING * ui
        val channels = listOf(MeterRed to reading.red, MeterGreen to reading.green, MeterBlue to reading.blue)
        channels.forEachIndexed { i, pair ->
            val x = startX + i * (colW + gap)
            drawGoalPost(x, top, colW, colH, pair.first, ui, pair.second)
        }
    }
}


object NDAssist {
    const val HELP =
        "Meters the live picture against middle gray and suggests a screw-on ND — stops and ND number — to balance it. The app cannot set a filter."
    const val METER_TITLE = "ND"
    const val NOTATION_TITLE = "Units"
    const val NOTATION_HELP =
        "Stops vs middle gray, filter factor (ND16 / ND32 / ND64), or optical density (ND 0.3 = 1 stop)."
}

@Composable
internal fun NDMeterPanel(state: LiveAssistState, modifier: Modifier = Modifier) {
    val transfer = state.scopeBundle.transfer
    val reading =
        NDFilterRecommendation.reading(state.scopeBundle.samples.histogramLuma, transfer)
    Box(
        modifier.fillMaxSize().padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            reading?.chipLabel(state.ndNotation) ?: "—",
            color = if (reading?.needsGlass == true) LiveDesign.accent else LiveDesign.text,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}



/**
 * Traces into [dstPlot] over the shared scope material (same rect as the 0 / 100 IRE
 * guides). The baked image is plot-sized and transparent aside from ticks, so
 * it does not stack a second plate (the black square) and L-scale cannot
 * drift IRE 100.
 */


private fun DrawScope.drawScopeTitle(measurer: TextMeasurer, title: String, chip: String) {
    val padX = 8.dp.toPx()
    val padY = 4.dp.toPx()
    drawText(
        measurer,
        title,
        Offset(padX, padY),
        TextStyle(color = LiveDesign.text.copy(alpha = 0.66f), fontSize = 10.5.sp, fontFamily = com.opencapture.openpocketcine.OpcFonts.sora, fontWeight = FontWeight.Bold),
    )
    val chipLayout =
        measurer.measure(
            chip,
            TextStyle(color = LiveDesign.text.copy(alpha = 0.58f), fontSize = 9.5.sp, fontFamily = com.opencapture.openpocketcine.OpcFonts.sora, fontWeight = FontWeight.Bold),
        )
    drawText(chipLayout, topLeft = Offset(size.width - chipLayout.size.width - padX, 5.dp.toPx()))
}






private fun DrawScope.drawGoalPost(
    x: Float,
    top: Float,
    colW: Float,
    colH: Float,
    color: Color,
    ui: Float,
    channel: ScopeChannelLight,
) {
    val indicator = TrafficLightsAssist.INDICATOR_SIZE * ui
    val postGap = TrafficLightsAssist.POST_SPACING * ui
    drawIndicator(x + colW / 2f, top + indicator / 2f, indicator, color, channel.clip, ui)
    val trackTop = top + indicator + postGap
    val trackH = colH
    val centerH = maxOf(1f, ui * TrafficLightsAssist.CENTER_LINE_FACTOR)
    val half = (trackH - centerH) / 2f
    val corner = CornerRadius(TrafficLightsAssist.TRACK_CORNER * ui)
    val shown = TrafficLightsAssist.channelDisplay(channel.level)
    val barH = maxOf(TrafficLightsAssist.MIN_BAR_HEIGHT * ui, half * shown.barFill.toFloat())
    drawRoundRect(LiveDesign.text.copy(alpha = 0.08f), Offset(x, trackTop), Size(colW, half), corner)
    if (shown.side == TrafficLightsAssist.BarSide.OVER && shown.barFill > 0) {
        val fillTop = trackTop + half - barH
        drawRect(
            Brush.verticalGradient(
                colors = listOf(color.copy(alpha = 0.92f), color.copy(alpha = 0.35f)),
                startY = fillTop,
                endY = trackTop + half,
            ),
            Offset(x, fillTop),
            Size(colW, barH),
        )
    }
    drawRect(LiveDesign.text.copy(alpha = 0.14f), Offset(x, trackTop + half), Size(colW, centerH))
    drawRoundRect(LiveDesign.text.copy(alpha = 0.08f), Offset(x, trackTop + half + centerH), Size(colW, half), corner)
    if (shown.side == TrafficLightsAssist.BarSide.UNDER && shown.barFill > 0) {
        val fillTop = trackTop + half + centerH
        drawRect(
            Brush.verticalGradient(
                colors = listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0.92f)),
                startY = fillTop,
                endY = fillTop + barH,
            ),
            Offset(x, fillTop),
            Size(colW, barH),
        )
    }
    val crushY = trackTop + trackH + postGap + indicator / 2f
    drawIndicator(x + colW / 2f, crushY, indicator, color, channel.crush, ui)
}

private fun DrawScope.drawIndicator(cx: Float, cy: Float, size: Float, color: Color, hot: Boolean, ui: Float) {
    if (hot) {
        drawCircle(color, size / 2f, Offset(cx, cy))
    }
    drawCircle(
        color.copy(alpha = if (hot) 1f else 0.75f),
        size / 2f,
        Offset(cx, cy),
        style = Stroke(maxOf(1f, 1.5f * ui)),
    )
}

private fun ScopeAssistBundle.resolvedTransfer(colorMode: Int): MonitorTransfer =
    if (revision > 0L) transfer else MonitorTransfer.fromColorMode(colorMode)

private fun zoneColor(db: Double): Color =
    when {
        db >= AudioAssist.RED_FROM_DB -> MeterRed.copy(alpha = 0.95f)
        db >= AudioAssist.YELLOW_FROM_DB -> MeterYellow.copy(alpha = 0.95f)
        else -> MeterGreen.copy(alpha = 0.9f)
    }

@Composable
internal fun Modifier.scopePanelChrome(): Modifier =
    monitorMaterial(MonitorMaterial.Scope, PanelShape)
