package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.appkitnative.MonitorLiveFeedDisplay
import com.opencapture.opencine.appkitnative.MonitorLiveFeedOwners
import com.opencapture.opencine.appkitnative.MonitorLiveFeedHost
import com.opencapture.opencine.appkitnative.MonitorLiveFeedSource
import com.opencapture.opencine.appkitnative.MonitorFaceReadbackEpoch
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import com.opencapture.openinstacine.monitor.feed.LiveFeed


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

/** The actual live adapter; native fixtures exercise its frame factories and discard owner. */
internal fun monitorLiveFeedSource(sessionOwner: () -> PocketCameraSession): MonitorLiveFeedSource<LiveFaceDetector.Frame> =
    object : MonitorLiveFeedSource<LiveFaceDetector.Frame> {
        private val session get() = sessionOwner()
        override val decoder get() = session.decoder
        override val pictureIdentity: Any get() = session.connectedCamera ?: session
        override val faceReadbackEpoch: MonitorFaceReadbackEpoch?
            get() {
                if (session.phaseFlow.value != com.opencapture.opencine.insta360.shell.ConnectionPhase.LIVE ||
                    session.connectedCamera == null) return null
                val stream = session.faceReadbackStreamGeneration ?: return null
                val owned = session.control.state.value.session ?: return null
                val current = owned.snapshots.value
                if (current.connection != ConnectionState.Ready) return null
                return MonitorFaceReadbackEpoch(current.session, current.epoch, stream)
            }
        override val cameraName get() = session.connectedCamera?.name
        override val connection get() = session.phaseFlow.value.vocabularyPhase()
        override val recoveryState get() = session.recoveryState
        override val isFeedRecovering get() = session.isFeedRecovering
        override val isFocusResetAvailable get() = session.isFocusResetAvailable
        override val wantsFaceDetect get() = session.wantsFaceDetect
        override fun attachSurface(surface: Surface?) = session.attachSurface(surface)
        override fun noteLiveFrame() = session.noteLiveFrame()
        override fun retrySessionRecovery() = session.retrySessionRecovery()
        override fun wantsFaceFrame() = session.wantsFaceFrame()
        override fun faceFrame(bitmap: Bitmap) = LiveFaceDetector.Frame.of(bitmap)
        override fun discardUnsubmittedFaceFrame(frame: LiveFaceDetector.Frame, bitmap: Bitmap) = frame.release()
        override fun faceFrame(nv21: ByteArray, width: Int, height: Int) = LiveFaceDetector.Frame.nv21(nv21, width, height)
        override fun considerFaceFrame(frame: LiveFaceDetector.Frame) = session.considerFaceFrame(frame)
    }

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
    val liveState = remember(model) { MonitorOperatorLiveState() }
    val context = LocalContext.current
    val assist = model.assist
    LaunchedEffect(gimbalLimitPulse) {
        if (gimbalLimitPulse == 0) return@LaunchedEffect
        model.gimbalGamepad.pulseLimit(model, operatorHaptics)
    }
    val session = model.session
    val source = remember(session) { monitorLiveFeedSource { session } }
    val plan = rememberLiveFeedEffectsPlan(assist = assist, lutSelection = model.lutSelection, status = status,
        family = session.connectedCamera?.model?.family.orEmpty(), cameraName = session.connectedCamera?.name)
    MonitorLiveFeedHost(LiveFeed, source,
        owners = MonitorLiveFeedOwners(assist, model.scopeBus, model.inspectorPreview),
        display = MonitorLiveFeedDisplay(plan, CameraCommands.liveViewFlip(poseViewFlip, assist.mirrorsHorizontally),
            model::chromeSectionMounts, model.portraitFeedAspect, model.virtualJoystickSize, model.hdrDisplayActive),
        cover = cover,
        onOperatorMenu = { model.disconnect() }) {
        // Current scene observations, precision and operator actions remain app-owned.
        val flipV = assist.flipsVertically
        val focusOffCenter = session.isFocusResetAvailable
        val faceMetering by session.faceMetering.collectAsState()
        val metering = faceMetering?.let { MonitorOperatorMeteringTile(it) { session.setFaceMetering(!it) } }
        val chrome = rememberOperatorChromeSource(model, status, capabilities)
        val focus = MonitorOperatorFocusObservation(focusPoint, trackingHud, session.supportsTapFocus,
            aeLock != null, model.focusBoxLocked, focusOffCenter)
        val focusActions = MonitorOperatorFocusActions(
            { x, y -> session.handleFeedTap(x, y); Unit },
            { box -> session.startTracking(box); Unit }, session::lockAutoExposure,
            { session.canLockAutoExposure }, { session.unlockAutoExposure() },
            { model.focusBoxLocked = !model.focusBoxLocked; model.focusBoxLocked },
            model::resetFocusPoint, { session.cancelSubjectTracking() }, session::presentControlNote)
        MonitorOperatorLiveSurface(chrome,
            geometry, liveState,
            cameraStatusLiveSource(chrome, geometry, liveState, link.label, link.bars, hasPicture, verticalPicture,
                mirrored = mirrored, recovering = recovering, busy = controlBusy, note = controlNote,
                clearNote = session::clearControlNoteIf,
                readExposure = { status.meteredEv.takeIf { it >= 0 } ?: pictureMeteredEv(session, assist, status) },
                exposureAvailable = !recovering && !session.isFeedRecovering,
                level = session.levelReading,
                levelViewFlip = CameraCommands.liveInvertPan(poseInvertPan, assist.mirrorsHorizontally) != flipV,
                vpnActive = { LocalVPNProbe.isActive(context) }, metering = metering),
            rememberOperatorAssistSource(model, status), focus, focusActions, nativeInputBlocked = { reason ->
                model.gimbalGamepad.noteBlocked(model)
                model.endGimbalStick()
                if (reason == MonitorInputBlock.LOCK) session.cancelProgrammedMove()
            }, modifier = modifier, picture = picture)
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
