package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.statusPresentation

import com.opencapture.monitorui.MonitorExposureReadout
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import com.opencapture.opencine.appkit.ShellModel
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.opencapture.monitorui.monitorReadoutShadow
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.opencapture.monitorui.MonitorQuickGestureOwner
import com.opencapture.monitorui.monitorReadoutGesture
import com.opencapture.monitorui.monitorPickerPassthrough
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.assists.AssistToolGlyph
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.session.ApertureStrategy
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.math.max
import kotlin.math.min

data class PortraitZones(
    val topBar: ChromeRect,
    val feed: ChromeRect,
    val assistToolbar: ChromeRect,
    val controls: ChromeRect,
    val systemBar: ChromeRect,
)

object LivePortraitMetrics {
    val TOP_BAR get() = 44f * LiveChromeMetrics.scale
    val TOP_BAR_LIFT get() = 8f * LiveChromeMetrics.scale
    val SYSTEM_BAR get() = 100f * LiveChromeMetrics.scale
    val SYSTEM_BAR_LIFT get() = 14f * LiveChromeMetrics.scale
    val CAPTURE get() = 64f * LiveChromeMetrics.scale
    val ASSIST get() = 58f * LiveChromeMetrics.scale
    val TOGGLE get() = 40f * LiveChromeMetrics.scale
    val TOGGLE_GAP get() = 8f * LiveChromeMetrics.scale
    val ASSIST_RAIL_EXPANDED get() = 60f * LiveChromeMetrics.scale
    val ASSIST_RAIL_COLLAPSED get() = 44f * LiveChromeMetrics.scale
    val ASSIST_RAIL_EDGE get() = 10f * LiveChromeMetrics.scale
    val REC_OPTIONS get() = 40f * LiveChromeMetrics.scale
    val REC_OPTIONS_INSET get() = 10f * LiveChromeMetrics.scale
    val REC_OPTIONS_GAP get() = 8f * LiveChromeMetrics.scale

    val FIT_BELOW_FEED_SLOT: Float
        get() =
            max(
                TOGGLE_GAP + TOGGLE,
                LiveChromeMetrics.STICK_GAP + LiveChromeMetrics.ZOOM + LiveChromeMetrics.STICK_GAP +
                    LiveChromeMetrics.STICK + LiveChromeMetrics.STICK_INSET,
            )
}

fun portraitZones(
    viewportWidth: Float,
    viewportHeight: Float,
    safeTop: Float,
    safeBottom: Float,
    clean: Boolean,
    fill: Boolean,
    assistToolbarHeight: Float,
    feedAspectRatio: Float = 16f / 9f,
): PortraitZones {
    val layout = com.opencapture.monitorui.MonitorLayoutPolicy.portrait(
        viewportWidth, viewportHeight, safeTop, safeBottom, fill, !clean, feedAspectRatio,
    )
    fun com.opencapture.monitorui.MonitorRect.chrome() = ChromeRect(x, y, width, height)
    return PortraitZones(layout.status.chrome(), layout.picture.chrome(),
        ChromeRect(0f, layout.controlsFloor, viewportWidth, 0f), layout.values.chrome(), layout.system.chrome())
}

/** Actual visible status row, shared by tap and hold presentation routes. */
fun livePortraitReadoutFrame(layout: LiveMonitorLayout, zones: PortraitZones): ChromeRect =
    ChromeRect(zones.topBar.minX, zones.topBar.minY + 6f, layout.viewportWidth, zones.topBar.height)

/**
 * iOS `LiveViewScreen` fillCrop: landscape fill over-widens a 16:9 picture to
 * the well height, then clips to the well (center crop). Vertical Pocket fill
 * stays the pillarboxed 9:16 picture and does not use this.
 */
fun portraitFillCropContent(well: ChromeRect): ChromeRect {
    val contentWidth = well.height * 16f / 9f
    return ChromeRect(well.midX - contentWidth / 2f, well.minY, contentWidth, well.height)
}

fun portraitAspectToggle(viewportWidth: Float, floorY: Float): ChromeRect {
    val frame = com.opencapture.monitorui.MonitorLayoutPolicy.portraitAspect(viewportWidth, floorY)
    return ChromeRect(frame.x, frame.y, frame.width, frame.height)
}

fun portraitAssistToolbar(floorY: Float, tablet: Boolean): ChromeRect {
    val frame = com.opencapture.monitorui.MonitorLayoutPolicy.portraitAssists(floorY, tablet)
    return ChromeRect(frame.x, frame.y, frame.width, frame.height)
}

fun portraitOnFeedControls(
    viewportWidth: Float,
    floorY: Float,
    showGimbalButton: Boolean = false,
): GimbalCluster {
    val stickFrame = com.opencapture.monitorui.MonitorLayoutPolicy.portraitStick(viewportWidth, floorY)
    val zoomFrame = com.opencapture.monitorui.MonitorLayoutPolicy.portraitZoom(stickFrame)
    val gimbalFrame = com.opencapture.monitorui.MonitorLayoutPolicy.portraitGimbal(stickFrame, zoomFrame)
    val stick = ChromeRect(stickFrame.x, stickFrame.y, stickFrame.width, stickFrame.height)
    val zoom = ChromeRect(zoomFrame.x, zoomFrame.y, zoomFrame.width, zoomFrame.height)
    val controls =
        if (showGimbalButton) ChromeRect(gimbalFrame.x, gimbalFrame.y, gimbalFrame.width, gimbalFrame.height)
        else ChromeRect(0f, 0f, 0f, 0f)
    return GimbalCluster(stick, zoom, controls)
}

@Composable
fun LivePortraitChrome(
    model: AppModel,
    layout: LiveMonitorLayout,
    zones: PortraitZones,
    status: CameraStatus,
    uiLocked: Boolean,
    onLock: () -> Unit,
    sheet: LiveSheet?,
    onSheet: (LiveSheet?) -> Unit,
    assist: LiveAssistState,
    onAssistLongPress: (LiveAssistTool) -> Unit,
    chromeInteractive: Boolean,
    controlBusy: Boolean,
    focusOffCenter: Boolean,
    onFocusReset: () -> Unit,
    fpsLabel: String = "\u2014",
    bars: Int = 0,
    sourceIsVertical: Boolean = false,
    capabilities: com.opencapture.opencine.core.MonitorLayoutCapabilities = model.monitorLayout(),
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    readoutFrame: ChromeRect = livePortraitReadoutFrame(layout, zones),
    onAssistBoundsChanged: (ChromeRect?) -> Unit = {},
    captureQuickActive: Boolean = false,
) {
    val cover = model.liveCover()
    val captureOpen = sheet != null || captureQuickActive
    val desqueezeVisible = assist.isVisible(LiveAssistTool.DESQ)
    val fill = sourceIsVertical || (!desqueezeVisible && model.portraitFeedAspect == PortraitFeedAspect.FILL)
    val tablet = min(layout.viewportWidth, layout.viewportHeight) >= 600f
    val editing = model.chromeEditorMode
    val showsRecord = model.chromeSectionMounts(PocketDispSection.RAIL_RECORD) || status.isRecording
    val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR) &&
        cover == null && assist.configureTool == null
    val floorY = zones.assistToolbar.minY
    val showGimbalButton =
        capabilities.gimbal && model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK)
    val cluster = layout.gimbalCluster(showGimbalButton)
    val stick = cluster.stick
    val zoom = cluster.zoom
    val gimbalButton = cluster.controls
    val toggle = portraitAspectToggle(layout.viewportWidth, floorY)
    val rail = portraitAssistToolbar(floorY, tablet)

    Box(Modifier.fillMaxSize()) {

        if (showsAssist) {
            Box(
                Modifier
                    .liveModuleFrame(rail)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
            ) {
                com.opencapture.openpocketcine.assists.MonitorAssistCluster(
                    portrait = true, locked = uiLocked || !chromeInteractive,
                    isOn = assist::isOn, onToggle = { assist.toggle(it) }, onLongPress = onAssistLongPress,
                    showsAudio = model.showsAudio(status),
                    onBoundsChanged = onAssistBoundsChanged,
                )
            }
        }

        if (editing == null && !sourceIsVertical && !desqueezeVisible) {
            LivePortraitAspectToggle(
                fill = fill,
                locked = uiLocked,
                modifier = Modifier.liveModuleFrame(toggle).alpha(if (uiLocked) 0.4f else 1f),
                onClick = {
                    if (!uiLocked) {
                        model.updatePortraitFeedAspect(
                            if (fill) PortraitFeedAspect.FIT_16X9 else PortraitFeedAspect.FILL,
                        )
                    }
                },
            )
        }

        if (!captureOpen && capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) {
            val zoomReadout by model.session.zoomReadout.collectAsState()
            val zoomDialReadout by model.session.zoomDialReadout.collectAsState()
            val zoomPinching by model.session.zoomPinching.collectAsState()
            val zoomBlocked =
                CamFov.zoomNeedsColorHopWhileRecording(
                    model.session.zoomNextJump(),
                    status.colorMode,
                    status.isRecording,
                )
            LiveZoomChip(
                factor = zoomReadout,
                dialFactor = zoomDialReadout,
                locked = uiLocked,
                pinching = zoomPinching,
                dimmed = zoomBlocked,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked || zoomBlocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    model.session.setZoom(LiveZoom.nextJump(model.session.zoomCycleFrom(), model.monitorZoomStops().primary))
                },
                onDigitalCycle = model.monitorZoomStops().secondary.takeIf { it.isNotEmpty() }?.let { stops ->
                    { model.session.setZoom(LiveZoom.nextJump(model.session.zoomCycleFrom(), stops)) }
                },
                maximum = model.session.zoomMax(),
                opticalStops = if (3.0 in model.session.zoomStops()) listOf(1.0, 3.0) else listOf(1.0),
                onDial = model.session::updateZoomPinch,
                onDialEnd = model.session::endZoomPinch,
            )
        }

        if (!captureOpen && showGimbalButton && !gimbalButton.isEmpty) {
            LiveGimbalButton(
                locked = uiLocked,
                onClick = {
                    model.liveGimbalPanel =
                        if (model.liveGimbalPanel == LiveGimbalPanel.SHEET) LiveGimbalPanel.NONE
                        else LiveGimbalPanel.SHEET
                },
                modifier =
                    Modifier
                        .liveModuleFrame(gimbalButton)
                        .alpha(if (uiLocked) 0.4f else 1f),
            )
        }
        if (showGimbalButton) {
            Box(Modifier.liveModuleFrame(stick).alpha(if (captureOpen) 0f else 1f).chromeEditStroke(editing != null, true)) {
                LiveGimbalStick(
                    enabled = !captureOpen && !uiLocked && cover == null && chromeInteractive,
                    onMove = model::updateGimbalStick,
                    onRelease = model::endGimbalStick,
                    onRecenter = { model.session.performGimbalDoubleTap() },
                    onFlip = { model.session.flipGimbal() },
                )
            }
        }
        if (!captureOpen && showGimbalButton && chromeInteractive && !uiLocked && cover == null) {
            LiveGimbalOverlay(
                model = model,
                layout = layout,
                feed = layout.onFeed,
                joystickBounds = stick,
                zoomBounds = if (capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) zoom
                    else ChromeRect(0f, 0f, 0f, 0f),
                uiLocked = uiLocked,
            )
        }
        // Same slot as landscape: leading of the stick, on its bottom edge (iOS `focusReset`).
        if (!uiLocked && focusOffCenter && chromeInteractive) {
            Box(Modifier.liveModuleFrame(layout.focusReset)) {
                LiveFocusResetButton(onClick = onFocusReset)
            }
        }

    }
}

@Composable
fun LivePortraitAspectToggle(
    fill: Boolean,
    locked: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(LivePortraitMetrics.TOGGLE.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, LiveDesign.hairline, CircleShape)
            .chromeClickable(enabled = !locked, onClick = onClick)
            .semantics { contentDescription = if (fill) "Fit feed in frame" else "Fill frame with feed" },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(if (fill) OpcIcon.MINIMIZE else OpcIcon.MAXIMIZE, null, Modifier.size(15.dp), LiveDesign.text)
    }
}

@Composable
fun LiveCaptureStrip(
    status: CameraStatus,
    active: LiveSheet?,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    showFocus: Boolean = true,
    showAperture: Boolean = false,
    facePriority: Boolean = false,
    shutterUsesAngle: Boolean = false,
    onOpen: (LiveSheet) -> Unit,
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    model: AppModel? = null,
    onQuickActiveChange: (Boolean) -> Unit = {},
    quickBottomClearanceDp: Float = 0f,
    portrait: Boolean? = null,
) {
    val context = LocalContext.current
    val commonState = model?.session?.control?.state?.collectAsState()?.value
    val auto = status.expoMode == CameraCommands.EXPO_AUTO
    val aeLocked = model?.session?.aeLock?.collectAsState()?.value != null
    val awbLocked = model?.session?.awbLockKelvin?.collectAsState()?.value != null
    val faceMetering = model?.session?.faceMetering?.collectAsState()?.value
    val shutter = captureShutterReadout(
        status,
        shutterUsesAngle,
        OperatorPrefs.shutterAngleDegrees(context),
    )
    fun value(sheet: LiveSheet, label: String, readout: String, annotation: String? = null,
        valueIcon: OpcIcon? = null, badgeIcon: OpcIcon? = null) =
        com.opencapture.openpocketcine.monitor.MonitorValue(
            sheet.name, label, readout, selected = active == sheet, annotation = annotation,
            valueIcon = valueIcon, badgeIcon = badgeIcon,
        )
    commonState
    val values = buildList {
        add(value(LiveSheet.ISO, "ISO", captureReadoutLabel(LiveSheet.ISO, status, model, CaptureLists.isoChipValue(status))))
        add(value(LiveSheet.SHUTTER,
            if (auto) MonitorExposureReadout.autoEvCaption(status.shutterDenom)
            else "SHUTTER",
            if (auto) EvComp.fromRaw(status.evComp)?.label ?: "\u2014" else captureReadoutLabel(LiveSheet.SHUTTER, status, model, shutter),
            if (auto && facePriority) CaptureLists.FACE_PRIORITY_TITLE else null,
            badgeIcon = if (auto && facePriority) OpcIcon.SCAN else null))
        add(value(LiveSheet.EXPO, "EXPOSURE", if (aeLocked) CaptureLists.AE_LOCK
            else if (status.expoMode == CameraCommands.EXPO_MANUAL) "M" else if (auto) "A" else "\u2014"))
        // iOS `LunaMeteringTile`: two values, so a tap toggles in place; hidden until the camera reports it.
        if (faceMetering != null) add(com.opencapture.openpocketcine.monitor.MonitorValue(
            METER_TILE, "METER", if (faceMetering) "Face" else "Matrix"))
        add(value(LiveSheet.WB, "WB", captureReadoutLabel(LiveSheet.WB, status, model, CaptureLists.wbChipValue(status, awbLocked)),
            valueIcon = if (CaptureLists.wbIsAuto(status) && !awbLocked) OpcIcon.APERTURE else null))
        if (showFocus) add(value(LiveSheet.FOCUS, "FOCUS", status.focusLabel))
        if (showAperture) add(value(LiveSheet.APERTURE, "APERTURE", ApertureStrategy.tileValue(status)))
        if (model?.monitorLayout()?.audio != false && CaptureShutterPolicy.showsAudioControls(status.shootingMode)) {
            add(value(LiveSheet.AUDIO, "AUDIO", status.audioLabel))
        }
    }
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val quickLifetime = rememberCaptureQuickLifetime(model)
    val isPortrait = portrait ?: (configuration.screenHeightDp > configuration.screenWidthDp)
    com.opencapture.openpocketcine.monitor.MonitorCameraValues(
        values = values,
        enabled = enabled && quickLifetime.active,
        portrait = isPortrait,
        modifier = modifier,
        quickControl = { id -> if (id == METER_TILE) null else model?.let { captureQuickControl(LiveSheet.valueOf(id), status, it, context, quickLifetime) } },
        quickPreview = { id, preview, maxHeight ->
            model?.let {
                LiveControlSheet(LiveSheet.valueOf(id), it, status, locked = false,
                    onDismiss = {}, maxHeightDp = maxHeight, preview = preview,
                    portrait = isPortrait)
            }
        },
        onQuickActiveChange = onQuickActiveChange,
        quickBottomClearanceDp = quickBottomClearanceDp,
        onQuickCommit = { id, source, value -> model?.let {
            releaseCaptureQuickControl(LiveSheet.valueOf(id), source, value, it, context, quickLifetime,
                enabled && active == null)
        } },
        onOpen = { id ->
            if (id == METER_TILE) faceMetering?.let { model?.session?.setFaceMetering(!it) } else onOpen(LiveSheet.valueOf(id))
        },
        onFrame = { id, rect -> if (id != METER_TILE) onTileFrame(LiveSheet.valueOf(id), rect) },
    )
}

private const val METER_TILE = "METER"

private fun portraitStorageLabel(status: CameraStatus): String =
    CaptureLists.storageLabel(status, showDuration = false)

/** Native recording options occupy the bounded format slot in the shared status row. */
@Composable
internal fun LivePortraitStatus(model: AppModel, layout: LiveMonitorLayout, status: CameraStatus,
    uiLocked: Boolean, chromeInteractive: Boolean, sheet: LiveSheet?, onSheet: (LiveSheet?) -> Unit,
    fpsLabel: String, bars: Int, onQuickActivityChange: (Boolean) -> Unit) {
    val field = checkNotNull(layout.field)
    val tablet = field.tablet
    val readoutFrame = layout.topDeck
    val capabilities = model.monitorLayout()
            val recContext = LocalContext.current
            val recLifetime = rememberCaptureQuickLifetime(model)
            val recOwner = remember { MonitorQuickGestureOwner() }
            val recInteractive = !uiLocked && chromeInteractive
            val notifyTop by rememberUpdatedState<(Boolean) -> Unit> { onQuickActivityChange(it); if (it) onSheet(null) }
            LaunchedEffect(recOwner.active) { notifyTop(recOwner.active != null) }
            DisposableEffect(Unit) { onDispose { notifyTop(false) } }
    val common by model.session.control.state.collectAsState()
    common
    com.opencapture.monitorui.MonitorStatusChrome(field,
        model.session.control.statusPresentation(status.recordElapsedSec),
        showsTimecode = CaptureShutterPolicy.showsVideoTransport(status.shootingMode) && capabilities.timecode && model.chromeSectionMounts(PocketDispSection.TIMECODE),
        showsRecording = CaptureShutterPolicy.showsVideoTransport(status.shootingMode) && model.chromeSectionMounts(PocketDispSection.REC_READOUT),
        modifier = Modifier.monitorReadoutShadow(),
        storage = {
            if (model.chromeSectionMounts(PocketDispSection.STORAGE)) Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                SdCardGlyph(LiveDesign.text)
                Text(portraitStorageLabel(status).substringBefore(" ·"), style = LiveType.mono(13.5f, FontWeight.SemiBold))
            }
        }, link = {
            com.opencapture.openpocketcine.monitor.MonitorTelemetry(bars, fpsLabel,
                model.phoneBatteryPercent, status.batteryPercent, horizontal = true, showsPower = false)
        }, format = {
                val setupSheet = CaptureShutterPolicy.portraitSetupSheet(status.shootingMode)
                val setupIsMode = CaptureShutterPolicy.portraitSetupOpensMode(status.shootingMode)
                val setupValue = CaptureShutterPolicy.portraitSetupLabel(status)
                val setupCaption = CaptureShutterPolicy.portraitSetupCaption(
                    status, model.session.connectedCamera?.model?.family ?: "pocket", model.session.profile)
                val setupTint =
                    if (sheet == setupSheet || recOwner.active == setupSheet.name) LiveDesign.accent else LiveDesign.text
                // iOS: the format sits on the timecode line at its size; the color hangs smaller below.
                Box(
                    contentAlignment = Alignment.BottomEnd,
                    modifier = Modifier
                        .monitorReadoutGesture(
                            captureQuickControl(setupSheet, status, model, recContext, recLifetime),
                            recInteractive && recLifetime.active && (recOwner.owner == null || recOwner.owner == setupSheet.name),
                            { onSheet(if (sheet == setupSheet) null else setupSheet) },
                            { source, value ->
                                releaseCaptureQuickControl(setupSheet, source, value, model, recContext, recLifetime, recInteractive)
                            },
                            0f, recOwner, setupSheet.name,
                            { preview, maxHeight ->
                                LiveControlSheet(setupSheet, model, status, locked = false,
                                    onDismiss = {}, maxHeightDp = maxHeight, preview = preview,
                                    portrait = true)
                            },
                            fromTop = true, ceilingY = readoutFrame.maxY,
                            onPreviewBegin = { notifyTop(true) },
                        )
                        .clearAndSetSemantics {
                            contentDescription = if (setupIsMode) "Shooting mode" else "Recording options"
                            stateDescription = setupValue
                        },
                ) {
                    Text(
                        setupValue,
                        color = setupTint,
                        style = if (setupIsMode) LiveType.mono(12f, FontWeight.SemiBold)
                        else LiveType.mono(if (tablet) 25f else 23f, FontWeight.Medium),
                        maxLines = 1,
                        softWrap = false,
                    )
                    if (setupCaption != null) {
                        Text(
                            setupCaption,
                            color = setupTint,
                            style = LiveType.ui(11f, FontWeight.SemiBold),
                            maxLines = 1,
                            softWrap = false,
                            modifier = Modifier.offset(y = 18.dp).wrapContentWidth(Alignment.End, unbounded = true),
                        )
                    }
                }
        })
}
