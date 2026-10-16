package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.appkitnative.MonitorLiveFeedDisplay
import com.opencapture.opencine.appkitnative.MonitorLiveFeedOwners
import com.opencapture.opencine.appkitnative.MonitorLiveFeedHost
import com.opencapture.opencine.appkitnative.MonitorLiveFeedSource
import com.opencapture.opencine.appkitnative.MonitorFaceReadbackEpoch
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import com.opencapture.openinstacine.monitor.feed.LiveFeed


import com.opencapture.opencine.cameracontrols.*

import com.opencapture.opencine.appkit.MonitorInputBlock

import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.platform.LocalVPNProbe
import android.graphics.Bitmap
import android.view.Surface
import com.opencapture.opencine.appkit.ShellModel
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openinstacine.monitor.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openinstacine.monitor.session.LiveFaceDetector
import com.opencapture.openinstacine.monitor.session.vocabularyPhase
import kotlinx.coroutines.isActive

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
        // The tile acts only for the session, epoch and phase it was drawn for; unknown shows a dash.
        val meterControl by session.control.state.collectAsState()
        val meterSource = meterControl.snapshot?.let { it.session to it.epoch }
        val meterPhase by session.phaseFlow.collectAsState()
        val face = faceMetering
        val metering = MonitorOperatorMeteringTile(face, isCurrent = {
            model.session === session && session.control.state.value.snapshot?.let { it.session to it.epoch } == meterSource
                && session.phase == meterPhase && session.faceMetering.value == face
        }) { face?.let { session.setFaceMetering(!it) } }
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
