package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.MonitorLinkObservation
import com.opencapture.opencine.cameracontrols.rememberMonitorLinkReadout
import com.opencapture.opencine.cameracontrols.MonitorOperatorRecoveryCard
import com.opencapture.opencine.cameracontrols.*

import com.opencapture.opencine.appkit.MonitorInteractionContext
import com.opencapture.opencine.appkit.MonitorInteractionEffect
import com.opencapture.opencine.appkit.MonitorInputAdmission
import com.opencapture.opencine.appkit.MonitorInputBlock

import com.opencapture.opencine.appkit.monitorChromeEditStroke
import com.opencapture.opencine.appkit.MonitorChromeEditBadgeLayer
import com.opencapture.opencine.appkit.MonitorChromeEditBanner
import com.opencapture.opencine.appkit.monitorChromeEditBoxes
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.LiveAutoExposureUnlockButton
import com.opencapture.opencine.cameracontrols.LiveControlSheet
import com.opencapture.opencine.cameracontrols.LiveFeedGestureWell
import com.opencapture.opencine.cameracontrols.LiveFocusResetButton
import com.opencapture.opencine.cameracontrols.LiveGimbalButton
import com.opencapture.opencine.cameracontrols.LiveGimbalOverlay
import com.opencapture.opencine.cameracontrols.LiveGimbalPanel
import com.opencapture.opencine.cameracontrols.LiveGimbalSheetHost
import com.opencapture.opencine.cameracontrols.LiveGimbalStick
import com.opencapture.opencine.cameracontrols.LivePickerHost
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.LiveZoom
import com.opencapture.opencine.cameracontrols.LiveZoomChip
import com.opencapture.opencine.cameracontrols.LocalLiveCanvasOrigin
import com.opencapture.opencine.cameracontrols.SdCardGlyph
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.cameracontrols.hidesLowerCaptureValues
import com.opencapture.opencine.cameracontrols.isTopAnchored
import com.opencapture.opencine.cameracontrols.opening
import com.opencapture.opencine.cameracontrols.reportChromeFrame
import com.opencapture.opencine.cameracontrols.retainedSheet
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.opencine.runtime.MonitorHDRDisplay
import com.opencapture.monitorui.portraitZones
import com.opencapture.monitorui.portraitAssistToolbar
import com.opencapture.monitorui.portraitFillCropContent
import com.opencapture.monitorui.livePortraitReadoutFrame
import com.opencapture.monitorui.LivePortraitMetrics
import com.opencapture.monitorui.monitorChromeScale
import com.opencapture.monitorui.monitorLeadingInsetDp
import com.opencapture.monitorui.monitorBottomInsetDp
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceView
import android.view.TextureView
import com.opencapture.opencine.appkit.statusPresentation
import com.opencapture.opencine.appkit.ShellModel
import androidx.compose.foundation.Canvas
import com.opencapture.monitorui.monitorReadoutShadow
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import android.app.ActivityManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import com.opencapture.monitorui.MonitorQuickGestureOwner
import com.opencapture.monitorui.monitorReadoutGesture
import com.opencapture.opencine.core.LocalVPNFilter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.graphics.createBitmap
import com.opencapture.opencine.vocabulary.CamFov
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import com.opencapture.opencine.vocabulary.ControlHud
import com.opencapture.opencine.vocabulary.FocusOverlay
import com.opencapture.opencine.vocabulary.FocusResetPolicy
import com.opencapture.opencine.vocabulary.LiveFeedFocusGesture
import com.opencapture.opencine.vocabulary.VideoResolution
import com.opencapture.openinstacine.monitor.assists.AssistLongPress
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.openinstacine.monitor.feed.FeedEffectsRenderPlan
import com.opencapture.opencine.media.FeedPresentPolicy
import com.opencapture.openinstacine.monitor.feed.GpuOverlayBus
import com.opencapture.openinstacine.monitor.feed.LiveFeedEffectsSession
import com.opencapture.openinstacine.monitor.feed.LiveVulkanSession
import com.opencapture.openinstacine.monitor.feed.LocalGpuLive
import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.monitorui.portraitVerticalPicture
import com.opencapture.openinstacine.monitor.feed.MonitorBackdropFeed
import com.opencapture.openinstacine.monitor.feed.rememberMonitorBackdropFeed
import com.opencapture.openpocketcine.feed.OpcVulkan
import com.opencapture.openinstacine.monitor.feed.appVulkanCrashGuard
import com.opencapture.openinstacine.monitor.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.session.LiveFaceDetector
import com.opencapture.openinstacine.monitor.session.vocabularyPhase
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import com.opencapture.monitorui.LiveChromeMetrics
import com.opencapture.opencine.cameracontrols.PortraitFeedAspect

@Composable
fun LiveViewScreen(model: AppModel) {
    val cover = model.liveCover()
    val status by model.session.chromeStatus.collectAsState()
    val capabilities = model.monitorLayout()
    val cameraGalleryOpen by model.session.cameraGalleryOpen.collectAsState()
    var followedGallery by remember { mutableStateOf(cameraGalleryOpen) }
    LaunchedEffect(cameraGalleryOpen) {
        if (cameraGalleryOpen == followedGallery) return@LaunchedEffect
        followedGallery = cameraGalleryOpen
        val shown = model.shell.state.value.cover
        if (cameraGalleryOpen && shown == null) {
            model.shell.open(ShellModel.Cover.MEDIA)
        } else if (!cameraGalleryOpen && shown == ShellModel.Cover.MEDIA) {
            model.shell.dismissCover()
        }
    }
    val controlNote by model.session.controlNote.collectAsState()
    val controlBusy by model.session.controlBusy.collectAsState()
    val focusPoint by model.session.focusPoint.collectAsState()
    val trackingHud by model.session.trackingHud.collectAsState()
    val aeLock by model.session.aeLock.collectAsState()
    val poseViewFlip by model.session.gimbalPoseViewFlip.collectAsState()
    val poseInvertPan by model.session.gimbalPoseInvertPan.collectAsState()
    val gimbalLimitPulse by model.session.gimbalLimitPulse.collectAsState()
    val operatorHaptics = LocalOperatorHaptics.current
    var tick by remember { mutableIntStateOf(0) }
    val liveState = remember(model) { MonitorOperatorLiveState() }
    val context = LocalContext.current
    val assist = model.assist
    val wantedViewFlip = CameraCommands.liveViewFlip(poseViewFlip, assist.mirrorsHorizontally)
    // MIRROR Vertical has no pose latch, so it applies on the toggle.
    val flipV = assist.flipsVertically
    var liveViewFlip by remember { mutableStateOf(wantedViewFlip) }
    LaunchedEffect(wantedViewFlip) {
        if (liveViewFlip == wantedViewFlip) return@LaunchedEffect
        delay(FeedPresentPolicy.EXTRA_MIRROR_HOLD_MS)
        liveViewFlip = wantedViewFlip
    }


    val recovery by model.session.recoveryState.collectAsState()
    val verticalPicture by model.session.decoder.isVerticalPicture.collectAsState()
    val hasPicture by model.session.decoder.hasPicture.collectAsState()

    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            tick += 1
        }
    }

    LaunchedEffect(gimbalLimitPulse) {
        if (gimbalLimitPulse == 0) return@LaunchedEffect
        model.gimbalGamepad.pulseLimit(model, operatorHaptics)
    }

    tick

    val glass = remember { MonitorGlass(GlassTier.FLAT) }
    val backdrop = rememberMonitorBackdropFeed(model.session.connectedCamera ?: model.session,
        enabled = cover == null && hasPicture)

    var vulkanFailed by remember { mutableStateOf(false) }
    val vulkanSession =
        remember {
            if (OpcVulkan.isAvailable && !appVulkanCrashGuard.isTripped(context)) {
                LiveVulkanSession(
                    context = context,
                    scopeBus = model.scopeBus,
                    preview = model.inspectorPreview,
                    backdrop = backdrop,
                    onDecoderSurface = { model.session.attachSurface(it) },
                    onFirstFrame = { model.session.noteLiveFrame() },
                    onFailed = { vulkanFailed = true },
                    onFramePresented = { model.session.decoder.notePresented(it) },
                )
            } else {
                null
            }
        }
    DisposableEffect(vulkanSession) {
        onDispose {
            vulkanSession?.release()
            model.session.attachSurface(null)
        }
    }
    val useVulkan = vulkanSession != null && !vulkanFailed
    val scopeSourceIdentity = model.session.connectedCamera ?: model.session
    val scopeSourceActive = cover != ShellModel.Cover.MEDIA
    LaunchedEffect(vulkanSession, useVulkan, scopeSourceIdentity, hasPicture, scopeSourceActive) {
        vulkanSession?.configureScopeSource(scopeSourceIdentity, hasPicture, scopeSourceActive && useVulkan)
    }
    val link = rememberMonitorLinkReadout(Triple(model.session, useVulkan, vulkanSession)) {
        MonitorLinkObservation(
            connection = model.session.phaseFlow.value.vocabularyPhase(),
            framesPresented =
                if (useVulkan) vulkanSession?.framesPresented?.get() ?: 0 else model.session.decoder.framesPresented.get(),
            lastPresentedAtMillis = model.session.decoder.lastPresentedAt,
            feedRecovering = model.session.isFeedRecovering,
            sessionRecovering = model.session.recoveryState.value.isRecovering,
        )
    }

    CompositionLocalProvider(LocalMonitorGlass provides glass, LocalMonitorBackdrops provides listOf(backdrop.source),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides if (useVulkan) Color.Black else LiveDesign.background) {
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(if (useVulkan) Color.Transparent else LiveDesign.background)
            .windowInsetsPadding(WindowInsets.navigationBars),
    ) {
        val density = LocalDensity.current
        val layoutDir = LocalLayoutDirection.current
        val cutout = WindowInsets.displayCutout
        val portrait = maxHeight > maxWidth
        val chromeScale =
            monitorChromeScale(LocalConfiguration.current.smallestScreenWidthDp.toFloat())
        LiveChromeMetrics.scale = chromeScale
        // Navigation is consumed by the outer viewport. Only cutouts and a
        // temporarily revealed status bar remain inside the live safe area.
        // Landscape leading is floored at the iPhone island lane so the 16:9
        // feed sits right of lock/battery (OpenZCine `monitorLeadingInsetDp`).
        // Trailing gets no floor; `feedFrame` yields a RAIL_W lane so the
        // record rail clears the picture.
        fun edgeDp(cutoutPx: Int, barPx: Int): Float =
            with(density) { maxOf(cutoutPx, barPx).toDp().value }
        val safeTop by animateFloatAsState(
            edgeDp(cutout.getTop(density), WindowInsets.systemBars.getTop(density)),
            label = "safeTop",
        )
        val safeBottom by animateFloatAsState(
            monitorBottomInsetDp(
                rawInsetDp = edgeDp(cutout.getBottom(density), 0),
                isPortrait = portrait && cover == null,
            ),
            label = "safeBottom",
        )
        val safeLeading by animateFloatAsState(
            with(density) {
                val cutoutDp = cutout.getLeft(this, layoutDir).toDp().value
                if (portrait) {
                    cutoutDp
                } else {
                    monitorLeadingInsetDp(
                        cutoutDp = cutoutDp,
                        transientBarDp = 0f,
                        chromeScale = chromeScale,
                    )
                }
            },
            label = "safeLeading",
        )
        val safeTrailing = with(density) { cutout.getRight(this, layoutDir).toDp().value }
        val vw = maxWidth.value
        val vh = maxHeight.value
        val pictureAspect = model.session.decoder.pictureAspect.toFloat()
        val desqueezeVisible = assist.isVisible(MonitorAssistTool.DESQ)
        val focusOffCenter = model.session.isFocusResetAvailable
        val geometry = monitorOperatorLiveLayout(
            MonitorOperatorViewport(vw, vh, safeLeading, safeTrailing, safeTop, safeBottom, chromeScale,
                with(density) { cutout.getTop(this) > 0 || cutout.getBottom(this) > 0 ||
                    cutout.getLeft(this, layoutDir) > 0 || cutout.getRight(this, layoutDir) > 0 }),
            assist, model::chromeSectionMounts, model.portraitFeedAspect, pictureAspect, verticalPicture,
            model.virtualJoystickSize, focusOffCenter)
        val layout = geometry.layout
        val pictureContent = geometry.pictureContent
        val effectsPlan =
            rememberLiveFeedEffectsPlan(
                assist = assist,
                lutSelection = model.lutSelection,
                status = status,
                family = model.session.connectedCamera?.model?.family.orEmpty(),
                cameraName = model.session.connectedCamera?.name,
            )
        var vulkanSurfaceView by remember { mutableStateOf<SurfaceView?>(null) }
        LaunchedEffect(vulkanSurfaceView, model.hdrDisplayActive) {
            val surface = vulkanSurfaceView ?: return@LaunchedEffect
            MonitorHDRDisplay.apply(surface, enabled = model.hdrDisplayActive)
        }
        var glesTextureView by remember { mutableStateOf<TextureView?>(null) }
        val wantsFaceDetect by model.session.wantsFaceDetect.collectAsState()
        var canvasOrigin by remember { mutableStateOf(Offset.Zero) }
        DisposableEffect(vulkanSession) {
            GpuOverlayBus.onSlotsMoved = { vulkanSession?.slotsMoved() }
            model.session.decoder.onOutputSizeChanged = { w, h ->
                vulkanSession?.setSourceSize(w, h)
            }
            onDispose {
                GpuOverlayBus.onSlotsMoved = null
                model.session.decoder.onOutputSizeChanged = null
            }
        }
        LaunchedEffect(
            useVulkan,
            effectsPlan,
            canvasOrigin,
            pictureContent,
            desqueezeVisible,
            density.density,
            liveViewFlip,
        ) {
            val session = vulkanSession ?: return@LaunchedEffect
            if (!useVulkan) return@LaunchedEffect
            val picture = if (desqueezeVisible) pictureContent else layout.onFeed
            session.setFeedRect(
                with(density) { picture.x.dp.toPx() },
                with(density) { picture.y.dp.toPx() },
                with(density) { picture.width.dp.toPx() },
                with(density) { picture.height.dp.toPx() },
                stretchToRect = desqueezeVisible,
            )
            session.updateEffects(
                plan = effectsPlan,
                uiScale = density.density,
                pictureMirrored = liveViewFlip,
                pictureFlippedVertically = flipV,
            )
        }
        val readoutRegions = remember { com.opencapture.monitorui.MonitorReadoutRegions() }
        CompositionLocalProvider(
            com.opencapture.monitorui.LocalMonitorReadoutRegions provides readoutRegions,
            LocalDensity provides Density(density.density, density.fontScale * chromeScale),
            LocalLiveCanvasOrigin provides canvasOrigin,
            LocalGpuLive provides if (useVulkan) vulkanSession else null,
        ) {
        val faceMetering by model.session.faceMetering.collectAsState()
        val meterOwner = model.session
        val meterControl by meterOwner.control.state.collectAsState()
        val meterSource = meterControl.snapshot?.let { it.session to it.epoch }
        val meterPhase = meterOwner.phase
        val metering = faceMetering?.let { face -> MonitorOperatorMeteringTile(face, isCurrent = {
            model.session === meterOwner && meterOwner.control.state.value.snapshot?.let { it.session to it.epoch } == meterSource
                && meterOwner.phase == meterPhase && meterOwner.faceMetering.value == face
        }) { meterOwner.setFaceMetering(!face) } }
        val chrome = rememberOperatorChromeSource(model, status, capabilities)
        val focus = MonitorOperatorFocusObservation(focusPoint, trackingHud, model.session.supportsTapFocus,
            aeLock != null, model.focusBoxLocked, focusOffCenter)
        val focusActions = MonitorOperatorFocusActions(
            { x, y -> model.session.handleFeedTap(x, y); Unit },
            { box -> model.session.startTracking(box); Unit }, model.session::lockAutoExposure,
            { model.session.canLockAutoExposure }, { model.session.unlockAutoExposure() },
            { model.focusBoxLocked = !model.focusBoxLocked; model.focusBoxLocked },
            model::resetFocusPoint, { model.session.cancelSubjectTracking() }, model.session::presentControlNote)
        MonitorOperatorLiveSurface(chrome,
            geometry, liveState,
            cameraStatusLiveSource(chrome, geometry, liveState, link.label, link.bars, hasPicture, verticalPicture,
                mirrored = liveViewFlip, recovering = recovery.isRecovering, busy = controlBusy, note = controlNote,
                clearNote = model.session::clearControlNoteIf,
                readExposure = { status.meteredEv.takeIf { it >= 0 } ?: pictureMeteredEv(model.session, assist, status) },
                exposureAvailable = !recovery.isRecovering && !model.session.isFeedRecovering,
                level = model.session.levelReading,
                levelViewFlip = CameraCommands.liveInvertPan(poseInvertPan, assist.mirrorsHorizontally) != flipV,
                vpnActive = { LocalVPNProbe.isActive(context) }, metering = metering),
            rememberOperatorAssistSource(model, status), focus, focusActions, nativeInputBlocked = { reason ->
                model.gimbalGamepad.noteBlocked(model)
                model.endGimbalStick()
                if (reason == MonitorInputBlock.LOCK) model.session.cancelProgrammedMove()
            }, modifier = Modifier.onGloballyPositioned { if (!useVulkan) canvasOrigin = it.positionInRoot() },
            picture = {
            if (useVulkan) {
                VulkanLivePresenter(
                    session = checkNotNull(vulkanSession),
                    onSurfaceView = { vulkanSurfaceView = it },
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .onGloballyPositioned { canvasOrigin = it.positionInRoot() },
                )
            }
            // The native image stays in its existing SurfaceView/TextureView.
            if (!useVulkan) {
            Box(
                Modifier
                    .liveModuleFrame(layout.onFeed)
                    .clipToBounds(),
            ) {
                LiveFeedPresenter(
                    mirrored = liveViewFlip,
                    flippedVertically = flipV,
                    stretchToRect = desqueezeVisible,
                    backdrop = backdrop,
                    scopeBus = model.scopeBus,
                    preview = model.inspectorPreview,
                    sourceIdentity = model.session.connectedCamera ?: model.session,
                    sourceReady = hasPicture,
                    sourceActive = scopeSourceActive,
                    plan = effectsPlan,
                    onDecoderSurface = { model.session.attachSurface(it) },
                    onPresented = { model.session.noteLiveFrame() },
                    onSourcePresented = { model.session.decoder.notePresented(it) },
                    onTextureView = { glesTextureView = it },
                    modifier =
                        Modifier
                            .offset(
                                (pictureContent.x - layout.onFeed.x).dp,
                                (pictureContent.y - layout.onFeed.y).dp,
                            )
                            .size(pictureContent.width.dp, pictureContent.height.dp),
                )
            }
            }

            // Passive source geometry; this box draws and captures nothing.
            Box(Modifier.liveModuleFrame(layout.onFeed).monitorBackdropSource(backdrop.source,
                imageRect = androidx.compose.ui.geometry.Rect(
                    (pictureContent.x - layout.onFeed.x) * density.density,
                    (pictureContent.y - layout.onFeed.y) * density.density,
                    (pictureContent.maxX - layout.onFeed.x) * density.density,
                    (pictureContent.maxY - layout.onFeed.y) * density.density), mirrored = liveViewFlip,
                flippedVertically = flipV))


            LiveFaceFramePump(surfaceView = vulkanSurfaceView, textureView = glesTextureView,
                feed = layout.onFeed, enabled = wantsFaceDetect && hasPicture,
                wantsFrame = model.session::wantsFaceFrame, onFrame = { model.session.considerFaceFrame(it) })
            })
        Box(Modifier.fillMaxSize().zIndex(20f)) {
            val panel = cover
            LaunchedEffect(panel) {
                assist.configureTool = null
                if (panel == null) {
                    val ready = vulkanSession?.windowReady == true
                    DiagnosticCenter.log(
                        "info",
                        "feed",
                        "overlay",
                        "feed: overlay dismissed windowReady=${if (ready) 1 else 0} " +
                            "frames=${vulkanSession?.framesPresented?.get() ?: -1}",
                    )
                    vulkanSession?.redrawLast()
                } else {
                    DiagnosticCenter.log(
                        "info",
                        "feed",
                        "overlay",
                        "feed: overlay held $panel windowReady=${if (vulkanSession?.windowReady == true) 1 else 0}",
                    )
                }
            }


                    }
        Box(Modifier.fillMaxSize().zIndex(30f)) {
            // The shared card owns the first-retry grace and the 48 dp actions (A3-24).
            MonitorOperatorRecoveryCard(
                recovery, model.session.connectedCamera?.name.orEmpty(),
                onRetry = { model.session.retrySessionRecovery() },
                onOperatorMenu = { model.disconnect() },
            )
        }

        }
    }
    }
}

@Composable
private fun LiveFaceFramePump(
    surfaceView: SurfaceView?,
    textureView: TextureView?,
    feed: ChromeRect,
    enabled: Boolean,
    wantsFrame: () -> Boolean,
    onFrame: (LiveFaceDetector.Frame) -> Unit,
) {
    val density = LocalDensity.current
    val handler = remember { Handler(Looper.getMainLooper()) }
    val inFlight = remember { AtomicBoolean(false) }
    val latest = rememberUpdatedState(onFrame)
    val wanted = rememberUpdatedState(wantsFrame)
    val vulkan = LocalGpuLive.current
    val faceInput = remember(surfaceView, textureView, vulkan, enabled) {
        com.opencapture.openinstacine.monitor.session.FaceFrameInput { failure ->
            DiagnosticCenter.log("error", "faceAF", "input", "faceAF input unavailable class=${failure.javaClass.simpleName}")
        }
    }
    LaunchedEffect(surfaceView, textureView, vulkan, enabled, feed.x, feed.y, feed.width, feed.height) {
        if (!enabled) return@LaunchedEffect
        val tapW = LiveFaceDetector.TAP_WIDTH
        while (isActive) {
            delay(LiveFaceDetector.INTERVAL_MS)
            if (faceInput.failed) return@LaunchedEffect
            // Vulkan: identity 720p RGB, same space as iOS Vision / 0xA6.
            // PixelCopy of the swapchain is already mirrored when TT180/MIRROR
            // is on, and the overlay mirrors again , box on the opposite side.
            val session = vulkan
            if (session != null) {
                // Take a fresh readback first, then ask for the next only when the
                // detector will use it (10 Hz idle pace skips the GPU readback too).
                session.takeFaceNv21()?.let {
                    faceInput.nv21(it, LiveFaceDetector.TAP_WIDTH, LiveFaceDetector.TAP_HEIGHT)?.let(latest.value)
                }
                if (wanted.value()) session.requestFaceTap()
                continue
            }
            if (!wanted.value() || !inFlight.compareAndSet(false, true)) continue
            val tapH =
                ((tapW * feed.height / feed.width.coerceAtLeast(1f)).toInt() and 1.inv())
                    .coerceAtLeast(16)
            val gles = textureView
            if (gles != null && gles.isAvailable) {
                val src = gles.getBitmap(tapW, tapH)
                inFlight.set(false)
                if (src != null) faceInput.of(src)?.let(latest.value)
                continue
            }
            val view = surfaceView
            if (view == null || !view.holder.surface.isValid) {
                inFlight.set(false)
                continue
            }
            val left = with(density) { feed.x.dp.toPx() }.roundToInt().coerceAtLeast(0)
            val top = with(density) { feed.y.dp.toPx() }.roundToInt().coerceAtLeast(0)
            val right =
                (left + with(density) { feed.width.dp.toPx() }.roundToInt())
                    .coerceAtMost(view.width.coerceAtLeast(left + 1))
            val bottom =
                (top + with(density) { feed.height.dp.toPx() }.roundToInt())
                    .coerceAtMost(view.height.coerceAtLeast(top + 1))
            if (right - left < 8 || bottom - top < 8) {
                inFlight.set(false)
                continue
            }
            val dest = createBitmap(tapW, tapH, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(
                    view,
                    Rect(left, top, right, bottom),
                    dest,
                    { result ->
                        inFlight.set(false)
                        if (result == PixelCopy.SUCCESS) {
                            faceInput.of(dest)?.let(latest.value)
                        } else {
                            dest.recycle()
                        }
                    },
                    handler,
                )
            } catch (_: Exception) {
                inFlight.set(false)
                dest.recycle()
            }
        }
    }
}

@Composable
private fun VulkanLivePresenter(
    session: LiveVulkanSession,
    onSurfaceView: (SurfaceView?) -> Unit,
    modifier: Modifier = Modifier,
) {
    DisposableEffect(Unit) { onDispose { onSurfaceView(null) } }
    AndroidView(
        factory = { viewContext ->
            com.opencapture.opencine.runtime.MonitorSurfacePictureHost(
                viewContext, attach = session::attachWindow, detach = session::detachWindow,
                journal = { DiagnosticCenter.log("info", "feed", "surface", it) },
            ).also(onSurfaceView)
        },
        modifier = modifier,
    )
}

/** GLES fallback; the same bounded raw tap supplies chrome after the native present. */
@Composable
private fun LiveFeedPresenter(
    mirrored: Boolean,
    flippedVertically: Boolean,
    stretchToRect: Boolean,
    backdrop: MonitorBackdropFeed,
    scopeBus: com.opencapture.opencine.runtime.ScopeSampleBus,
    preview: com.opencapture.opencine.runtime.InspectorPreviewPipeline,
    sourceIdentity: Any,
    sourceReady: Boolean,
    sourceActive: Boolean,
    plan: FeedEffectsRenderPlan,
    onDecoderSurface: (Surface) -> Unit,
    onPresented: () -> Unit = {},
    onSourcePresented: (Long) -> Unit = {},
    onTextureView: (TextureView?) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val attach = rememberUpdatedState(onDecoderSurface)
    val presented = rememberUpdatedState(onPresented)
    val sourcePresented = rememberUpdatedState(onSourcePresented)
    val textureViewOut = rememberUpdatedState(onTextureView)
    val context = LocalContext.current
    var gpuFailed by remember { mutableStateOf(false) }
    val session =
        remember {
            LiveFeedEffectsSession(
                context = context,
                scopeBus = scopeBus,
                preview = preview,
                backdrop = backdrop,
                onDecoderSurface = { attach.value(it) },
                onGpuFailed = { gpuFailed = true },
                onFirstFrame = { presented.value() },
                onFramePresented = { sourcePresented.value(it) },
            )
        }
    DisposableEffect(session) {
        onDispose {
            session.close()
            textureViewOut.value(null)
        }
    }
    LaunchedEffect(sourceIdentity, sourceReady, sourceActive) {
        session.configurePreviewSource(sourceIdentity, sourceReady, sourceActive)
    }
    LaunchedEffect(plan) { session.updatePlan(plan) }
    LaunchedEffect(stretchToRect) { session.setStretchToRect(stretchToRect) }

    Box(modifier.graphicsLayer {
        scaleX = if (mirrored) -1f else 1f
        scaleY = if (flippedVertically) -1f else 1f
    }) {
        key(gpuFailed) {
            AndroidView(
                factory = { viewContext ->
                    val program =
                        if (gpuFailed) com.opencapture.opencine.runtime.MonitorDecoderTextureProgram {
                            attach.value(it)
                        } else session.pictureProgram
                    com.opencapture.opencine.runtime.MonitorTexturePictureHost(
                        viewContext, program = program,
                        updated = { tv ->
                            if (gpuFailed) tv.surfaceTexture?.let { sourcePresented.value(it.timestamp) }
                            presented.value()
                        },
                        journal = { DiagnosticCenter.log("info", "feed", "surface", it) },
                    ).also { textureViewOut.value(it) }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }

    }
}
