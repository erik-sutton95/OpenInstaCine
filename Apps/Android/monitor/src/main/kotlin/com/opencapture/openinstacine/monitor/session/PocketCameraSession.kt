package com.opencapture.openinstacine.monitor.session

import kotlin.math.roundToInt
import com.opencapture.opencine.insta360.shell.label
import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.commitZoomCycle
import com.opencapture.opencine.cameracontrols.pendingZoom
import com.opencapture.opencine.motion.GimbalProgram
import com.opencapture.opencine.motion.GimbalWaypoint
import com.opencapture.opencine.motion.GimbalWaypointSlot
import com.opencapture.opencine.motion.LevelReading
import com.opencapture.opencine.motion.WorldLevelSnap
import com.opencapture.opencine.vocabulary.AutoExposureLock
import com.opencapture.opencine.vocabulary.CamFov
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraZoomProfile
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.ControlHud
import com.opencapture.opencine.vocabulary.EvComp
import com.opencapture.opencine.vocabulary.FaceAFPolicy
import com.opencapture.opencine.vocabulary.FaceTrackHold
import com.opencapture.opencine.vocabulary.FaceTrackTap
import com.opencapture.opencine.vocabulary.FocusOption
import com.opencapture.opencine.vocabulary.FocusOverlay
import com.opencapture.opencine.vocabulary.FocusOverlayPolicy
import com.opencapture.opencine.vocabulary.FocusResetPolicy
import com.opencapture.opencine.vocabulary.FoundCamera
import com.opencapture.opencine.vocabulary.GamepadOperatorAction
import com.opencapture.opencine.vocabulary.GamepadShutterSync
import com.opencapture.opencine.vocabulary.GimbalDoubleTap
import com.opencapture.opencine.vocabulary.GimbalHudCopy
import com.opencapture.opencine.vocabulary.GimbalLimitContact
import com.opencapture.opencine.vocabulary.GimbalMode
import com.opencapture.opencine.vocabulary.GimbalRamp
import com.opencapture.opencine.vocabulary.GimbalSpeed
import com.opencapture.opencine.vocabulary.SceneFacePolicy
import com.opencapture.opencine.vocabulary.SessionRecoveryEpisode
import com.opencapture.opencine.vocabulary.SessionRecoveryTrigger
import com.opencapture.opencine.vocabulary.SessionRecoveryUi
import com.opencapture.opencine.vocabulary.RecoveryPictureProof
import com.opencapture.opencine.vocabulary.ShutterAngle
import com.opencapture.opencine.vocabulary.TrackingBox
import com.opencapture.opencine.vocabulary.TrackingHud
import com.opencapture.opencine.vocabulary.TrackingStartPolicy
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.opencine.appkit.MonitorControlModel
import com.opencapture.opencine.appkit.MotionProgramSession
import com.opencapture.opencine.appkit.diagnostics.ReliabilityCameraPathLease
import com.opencapture.opencine.core.CameraCommandIntent
import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.insta360.luna.LunaCameraSession
import com.opencapture.opencine.insta360.luna.LunaConnectPort
import com.opencapture.opencine.insta360.luna.LUNA_RECOVERY_ATTEMPT_DEADLINE
import com.opencapture.opencine.insta360.luna.LunaFrameTimecode
import com.opencapture.opencine.insta360.luna.LunaMotionService
import com.opencapture.opencine.insta360.luna.LunaSubjectTracking
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.media.SerialSessionGate
import com.opencapture.opencine.decoder.HevcDecoder
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.diagnostics.AppDiagnostics
import com.opencapture.opencine.media.FeedDecoderErrorOrigin
import com.opencapture.opencine.media.FeedIncidentAges
import com.opencapture.opencine.media.FeedIncidentBreadcrumb
import com.opencapture.opencine.media.FeedIncidentBreadcrumbKind
import com.opencapture.opencine.media.FeedIncidentLifecycle
import com.opencapture.opencine.media.FeedIncidentQueue
import com.opencapture.opencine.media.FeedIncidentRateSampler
import com.opencapture.opencine.media.FeedIncidentStageCounts
import com.opencapture.opencine.media.FeedIncidentCounterEpoch
import com.opencapture.opencine.decoder.incidentDecoder
import com.opencapture.opencine.media.FeedIncidentSnapshot
import com.opencapture.opencine.media.FeedRepairPhase
import com.opencapture.opencine.media.FeedRepairRecord
import com.opencapture.opencine.media.RecoveryAction
import com.opencapture.opencine.media.RecoveryEffect
import com.opencapture.opencine.media.RecoveryEffectLog
import com.opencapture.opencine.media.RecoveryReason
import com.opencapture.openinstacine.monitor.BuildConfig
import android.os.Build
import java.util.UUID
import com.opencapture.opencine.insta360.shell.CameraTrackFrame
import com.opencapture.opencine.insta360.shell.CameraTrackState
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.Continuation
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.math.abs
import kotlin.math.hypot
import java.util.Locale
import com.opencapture.openinstacine.monitor.MonitorConfiguration
import com.opencapture.opencine.insta360.shell.CameraBackend
import com.opencapture.opencine.insta360.shell.CameraCapability
import com.opencapture.opencine.insta360.shell.CameraNotice
import com.opencapture.opencine.insta360.shell.CameraControls
import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import com.opencapture.opencine.insta360.shell.CameraIdentity
import com.opencapture.opencine.insta360.shell.CameraReadout
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.update
import com.opencapture.opencine.media.LivePipelineCadence

/**
 * OpenInstaCine session. Same view-facing surface as OpenPocketCine's DUML session, so every
 * shared screen binds unchanged; the Osmo spine is replaced by the injected [CameraBackend]
 * (Luna: BLE consent, camera Wi-Fi, UCD2 on TCP 6666). Controls exist only where the backend
 * advertises the capability and implements [CameraControls]; everything else is a no-op that
 * leaves the shared sheets on their unavailable state. Historical class name kept for JNI and
 * source compatibility with the upstream shell.
 */
class PocketCameraSession(
    context: Context,
    incidentSink: com.opencapture.opencine.media.FeedIncidentSink = AppDiagnostics.incidents,
    private val nativePinNow: () -> Long = SystemClock::elapsedRealtime,
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val backend: CameraBackend = MonitorConfiguration.createBackend(appContext)
    private val reportingOwner = Any()
    private val incidentSessionSink = AppDiagnostics.incidentSink(reportingOwner, incidentSink)
    private var feedIncidents: com.opencapture.opencine.media.FeedIncidentSource? = null
    private var incidentSessionActive = false
    private val incidentRateSampler = FeedIncidentRateSampler()
    private var closed = false

    // Reports stay held back from this session's connect attempt, through recovery and FAILED,
    // until it returns to IDLE, disconnects or closes; a retired facade only ends its own lease.
    private var reportingCameraPath: ReliabilityCameraPathLease? = null
    private fun holdReportingCameraPath() {
        if (!closed && reportingCameraPath == null) reportingCameraPath = AppDiagnostics.reporting.beginCameraPath()
    }
    private fun releaseReportingCameraPath() {
        reportingCameraPath?.close()
        reportingCameraPath = null
    }
    private val controls: CameraControls? = backend as? CameraControls
    /** This session's names and media host (STATE-01: per session, never a launch-time global). */
    val profile: CameraProfile = LunaShellMapping.profile
    /** This source's learned picture EV calibration (STATE-01: one meter per session, keyed by source). */
    internal val pictureEV by lazy { com.opencapture.openinstacine.monitor.PictureEVMeter.stored(appContext) }
    val capabilities: Set<CameraCapability> get() = backend.capabilities
    private fun can(capability: CameraCapability) = controls != null && capability in capabilities

    internal val cadence = LivePipelineCadence()
    @Volatile internal var debugVideoPacketAdmission: (() -> Boolean)? = null
    internal var debugCameraSetResult: ((Int, Boolean) -> Unit)? = null
    internal val pendingCameraSetCount: Int get() = 0
    val decoder = HevcDecoder(cadence, errorJournal = DiagnosticCenter::logDecoderError)
    /** The Luna gimbal requests (`LunaMotionService`). Before `init`: its live handler starts the angle poll. */
    private val motion = LunaMotionService({ controls }, scope)
    // Timecode, iOS `noteFrameClock`: live frame stamps to time of day (`LunaFrameTimecode`), with
    // the camera clock synced at live start (the backend). Before `init`: its collectors reset it.
    private val frameTimecode = LunaFrameTimecode()

    val phase: ConnectionPhase get() = backend.phase.value
    val phaseFlow: StateFlow<ConnectionPhase> get() = backend.phase
    val failure: StateFlow<String?> get() = backend.failure
    val radioOn: StateFlow<Boolean> get() = backend.radioOn

    private val _status = MutableStateFlow(CameraStatus())
    val status: StateFlow<CameraStatus> = _status.asStateFlow()
    val chromeStatus: StateFlow<CameraStatus> = _status.asStateFlow()
    val cameraGalleryOpen: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val levelReading = LevelReading()

    private val _controlNote = MutableStateFlow<String?>(null)
    val controlNote: StateFlow<String?> = _controlNote.asStateFlow()
    fun clearControlNoteIf(note: String) { if (_controlNote.value == note) _controlNote.value = null }
    fun presentControlNote(note: String) { _controlNote.value = note }
    private fun unavailable(what: String) = presentControlNote("$what is not available on the Luna Ultra yet.")

    /** A photo in flight; a record operation in flight is the shared model's `recordPending`. */
    private val _controlBusy = MutableStateFlow(false)
    /** Camera media over the control link, when the backend offers it (Luna: UCD2 list + HTTP). */
    val mediaCatalogRecords: com.opencapture.opencine.insta360.luna.LunaMediaCatalogRecordSource?
        get() = backend as? com.opencapture.opencine.insta360.luna.LunaMediaCatalogRecordSource
    private val pins = LunaControlPins()
    /**
     * The monitor's common controls (SHELL-03): ISO, shutter, white balance and record go only
     * through this shared model, which the app's shell binds to the connected camera's session.
     */
    val control = MonitorControlModel(scope)

    /** The rec lamp's busy state: a photo or a record operation in flight. */
    val controlBusy: StateFlow<Boolean> =
        combine(_controlBusy, control.state) { photo, shared -> photo || shared.recordPending }
            .stateIn(scope, SharingStarted.Eagerly, false)

    init {
        control.onNote = { presentControlNote(it) }
        control.noteFor = CorePresentation::note
        control.onChange = { retireChangedNativeCaptureSource(); _status.update(::projectControls) }
        control.onRecordFinished = { receipt ->
            val stopped = receipt.intent == CameraCommandIntent.StopRecording && receipt.stage == CommandStage.Confirmed
            if (stopped) _mediaCaptured.tryEmit(Unit)
        }
    }

    /** Temporary (I-1): the shared model's reported and pending ISO, shutter, WB and recording on the status. */
    private fun projectControls(status: CameraStatus): CameraStatus {
        val shared = control.state.value
        return shared.snapshot?.let { CorePresentation.apply(it, shared.pending, status) } ?: status
    }
    private var formatTable: Map<VideoFormat, Long> = emptyMap()
    private var lastReadout = CameraReadout()
    private val _nativeFormats = MutableStateFlow<List<com.opencapture.opencine.insta360.shell.CameraRecordFormat>>(emptyList())
    val nativeFormats = _nativeFormats.asStateFlow()
    private val _nativeFormat = MutableStateFlow<com.opencapture.opencine.insta360.shell.CameraRecordFormat?>(null)
    val nativeFormat = _nativeFormat.asStateFlow()
    private val _nativeColor = MutableStateFlow<com.opencapture.opencine.insta360.shell.CameraColorProfile?>(null)
    val nativeColor = _nativeColor.asStateFlow()
    private data class NativeCaptureSource(
        val session: com.opencapture.opencine.core.CameraSession,
        val epoch: com.opencapture.opencine.core.ControlEpoch,
        val authority: com.opencapture.opencine.core.ControlAuthority,
        val connectionGeneration: Long?,
        val lifetime: Long,
    )
    /** Each instance is the unique request token, even when an operator repeats a value. */
    private class NativeCapturePin<T>(val source: NativeCaptureSource, val value: com.opencapture.opencine.core.CameraValuePin<T>)
    private var nativeCaptureLifetime = 0L
    private var nativeFormatPin: NativeCapturePin<com.opencapture.opencine.insta360.shell.CameraRecordFormat>? = null
    private var nativeColorPin: NativeCapturePin<com.opencapture.opencine.insta360.shell.CameraColorProfile>? = null

    private fun nativeCaptureSource(): NativeCaptureSource? {
        val state = control.state.value
        val session = state.session ?: return null
        val snapshot = state.snapshot ?: return null
        if (closed || phase != ConnectionPhase.LIVE || snapshot.session != session.id ||
            snapshot.connection != com.opencapture.opencine.core.ConnectionState.Ready ||
            (snapshot.authority != com.opencapture.opencine.core.ControlAuthority.Owner &&
                snapshot.authority !is com.opencapture.opencine.core.ControlAuthority.Lease)) return null
        return NativeCaptureSource(session, snapshot.epoch, snapshot.authority, backend.frameConnectionGeneration, nativeCaptureLifetime)
    }
    private fun retireChangedNativeCaptureSource() {
        val source = nativeCaptureSource()
        if (nativeFormatPin?.source != source) nativeFormatPin = null
        if (nativeColorPin?.source != source) nativeColorPin = null
    }
    private fun retireNativeCaptureRequests() {
        nativeCaptureLifetime += 1
        nativeFormatPin = null; nativeColorPin = null; pins.faceMetering = null
    }
    private fun <T> nativeReadout(pin: NativeCapturePin<T>?, reported: T?, now: Long): Pair<T?, NativeCapturePin<T>?> {
        if (reported == null || pin == null || pin.source != nativeCaptureSource()) return reported to null
        val (held, retained) = com.opencapture.opencine.core.CameraValuePin.reconcile(pin.value, reported, now)
        return (held ?: reported) to if (retained == null) null else pin
    }
    private var recordStartedAt: Long? = null
    private val _focusPoint = MutableStateFlow(0.5f to 0.5f)
    val focusPoint: StateFlow<Pair<Float, Float>> = _focusPoint.asStateFlow()
    val gimbalPoseViewFlip: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val gimbalPoseInvertPan: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val gimbalLimitPulse: StateFlow<Int> = MutableStateFlow(0).asStateFlow()
    @Volatile var lastGimbalLimitContact = GimbalLimitContact()
    @Volatile var lastGimbalLimitPanSign = 0.0
    @Volatile var lastGimbalLimitTiltSign = 0.0
    private var isBrowsingMedia = false
    val browsingMedia: Boolean get() = isBrowsingMedia

    // The shared owner owns the take; this adapter supplies one captured Luna connection/epoch.
    private val programmedMove = MotionProgramSession(scope)
    private var programSceneActive = true
    val gimbalMoveCountdown: StateFlow<Int?> = programmedMove.state.map { it.progress.countdown }
        .stateIn(scope, SharingStarted.Eagerly, null)
    val gimbalMoveReadout: StateFlow<String> = MutableStateFlow("").asStateFlow()
    var gimbalRamp: GimbalRamp = GimbalRamp.OFF
    var gimbalDoubleTap: GimbalDoubleTap = GimbalDoubleTap.RECENTER
    private val _gimbalMode = MutableStateFlow(GimbalMode.FOLLOW)
    val gimbalMode: StateFlow<GimbalMode> = _gimbalMode.asStateFlow()
    private val _gimbalSpeed = MutableStateFlow(GimbalSpeed.DEFAULT)
    val gimbalSpeed: StateFlow<GimbalSpeed> = _gimbalSpeed.asStateFlow()
    private val _gimbalProgram = MutableStateFlow(GimbalProgram())
    val gimbalProgram: StateFlow<GimbalProgram> = _gimbalProgram.asStateFlow()
    val gimbalMovePaused: StateFlow<Boolean> = programmedMove.state.map { it.progress.paused }
        .stateIn(scope, SharingStarted.Eagerly, false)
    val gimbalMoveRunning: StateFlow<Boolean> = programmedMove.state.map { it.progress.running }
        .stateIn(scope, SharingStarted.Eagerly, false)
    val hasGimbal: Boolean get() = connectedCamera != null && controls != null && controlCapabilities().gimbal.isOffered
    val supportsZoom: Boolean get() = connectedCamera != null && controls != null && controlCapabilities().zoom.isOffered
    val canRunProgrammedMove: Boolean
        get() = programmedZoomUnavailableReason() == null && phase == ConnectionPhase.LIVE && hasVideoFormat &&
            _gimbalProgram.value.canRun
    // ponytail: lens zoom is not streamed with the move (iOS); add a zoom track when asked.
    @Suppress("UNUSED_PARAMETER")
    fun programmedZoomUnavailableReason(status: CameraStatus = _status.value): String? =
        if (_gimbalProgram.value.changesZoom) "Luna moves cannot change zoom. Set every point at one zoom." else null
    fun gimbalDebugText(): String = "luna gimbal: " + (gimbalAngle?.first?.let { "pitch %.1f yaw %.1f".format(Locale.US, it.pitch, it.yaw) } ?: "no angle")
    fun predictedGimbalWaypoint(nowSeconds: Double): GimbalWaypoint? = liveGimbalWaypoint
    val liveGimbalWaypoint: GimbalWaypoint? get() = freshGimbalAngle(500)?.let { LunaGimbalAim.waypoint(it, _zoomReadout.value) }

    var connectedCamera: FoundCamera? = null
    var joinedSSID: String? = null
    /** iOS `supportsFocusMode`: AF-S, AF-C and Product Showcase (option 93). */
    val supportsFocusMode: Boolean get() = controls != null && controlCapabilities().focus.isOffered
    val supportsTapFocus: Boolean get() = controls != null && controlCapabilities().tapFocus.isOffered
    /** iOS `reportsMeteredEV`: the Luna sends none, so the EV meter reads the picture. */
    val reportsMeteredEV: Boolean get() = CameraCapability.METERED_EV in capabilities
    /** DJI camcap hop to the log curve's native ISO on a color change; the Luna has none, so the ISO sheet hides the toggle. */
    val supportsNativeIsoHop: Boolean get() = controlCapabilities().nativeISO.hop == true
    /** iOS `faceMetering`: true Face Priority, false Matrix, null until the camera reports it (METER tile hidden). */
    private val _faceMetering = MutableStateFlow<Boolean?>(null)
    val faceMetering: StateFlow<Boolean?> = _faceMetering.asStateFlow()

    /** The calibration context of the picture EV estimate: device, recording profile and curve, metering. */
    internal fun pictureEVSource(transfer: com.opencapture.openinstacine.monitor.feed.MonitorTransfer) =
        com.opencapture.openinstacine.monitor.PictureEVMeter.Source(
            device = control.state.value.snapshot?.device?.value ?: connectedCamera?.id ?: "unknown",
            profile = _status.value.colorMode.toString(),
            transfer = transfer,
            metering = when (_faceMetering.value) { true -> "face"; false -> "matrix"; null -> "unknown" },
        )
    var videoPackets = 0
    var accessUnits = 0
    var framesEnqueued = 0
    var droppedIncomplete = 0
    var decoderErrors = 0
    var hasVideoFormat = false
    var nalTypes = ""
    var lastKeyframeAge = "—"
    var holdsMonitor = false

    private val _recoveryState = MutableStateFlow<SessionRecoveryUi>(SessionRecoveryUi.Idle)
    val recoveryState: StateFlow<SessionRecoveryUi> = _recoveryState.asStateFlow()
    val isFormatPinActive: Boolean get() = false
    @Volatile var zoomColorHopPending = false
    var zoomPinchPreview: Double? = null
    private var zoomPinchBase = 1.0
    private var zoomTarget: Double? = null
    val zoomOptimistic: Double? get() = zoomTarget
    // Face boxes (iOS `applyDetectedFaces`): on-phone detection while AF-C, dimmed boxes the operator taps to Deep Track.
    private val faceDetector = LiveFaceDetector()
    private val _faceAFArmed = MutableStateFlow(false)
    val faceAFArmed: StateFlow<Boolean> = _faceAFArmed.asStateFlow()
    private val _wantsFaceDetect = MutableStateFlow(false)
    val wantsFaceDetect: StateFlow<Boolean> = _wantsFaceDetect.asStateFlow()
    private var faceAFArmJob: Job? = null
    private var faceTickJob: Job? = null
    private var faceBox: TrackingBox? = null
    private var sceneFaces: List<TrackingBox> = emptyList()
    private var lastFaceHitAt: Long? = null
    private var lastFaceAt: Long? = null
    private var lastTapFocusAt: Long? = null
    /** A capture finished (photo, stop, or stopped on the camera): an open album re-lists (iOS `refreshMediaAfterCapture`). */
    private val _mediaCaptured = kotlinx.coroutines.flow.MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST)
    val mediaCaptured: kotlinx.coroutines.flow.SharedFlow<Unit> = _mediaCaptured
    private val _zoomReadout = MutableStateFlow(1.0)
    val zoomReadout: StateFlow<Double> = _zoomReadout.asStateFlow()
    val zoomDialReadout: StateFlow<Double> = _zoomReadout.asStateFlow()
    private val _zoomPinching = MutableStateFlow(false)
    val zoomPinching: StateFlow<Boolean> = _zoomPinching.asStateFlow()
    private val tracking = LunaSubjectTracking({ controls }, { refreshTrackingHud() })
    /** Deep Track boxes plus the AF-C face box and the dimmed scene faces (upstream `refreshTrackingHud`). */
    private fun refreshTrackingHud() {
        val track = tracking.snapshot
        val search = track.searchBox?.let(LunaShellMapping::trackingBox)
        val subject = track.subjectBox?.let(LunaShellMapping::trackingBox)
        val sinceTap = lastTapFocusAt?.let { (SystemClock.elapsedRealtime() - it) / 1000.0 }
        val overlay = if (FaceAFPolicy.shouldHoldTapBox(sinceTap)) {
            FocusOverlayPolicy.resolve(track.tracking, search, subject).takeUnless { it is FocusOverlay.Face } ?: FocusOverlay.Focus
        } else {
            FaceAFPolicy.resolve(_status.value.focusMode, track.tracking, search, subject, faceBox)
        }
        val hiding = (overlay as? FocusOverlay.Face)?.box
        val occluder = when (overlay) {
            is FocusOverlay.Subject -> overlay.box
            is FocusOverlay.Search -> overlay.box
            else -> subject
        }
        _trackingHud.value = TrackingHud(overlay, sceneFaces, SceneFacePolicy.dimmed(sceneFaces, hiding, occluder), isTracking = track.active)
    }
    private val _trackingHud = MutableStateFlow(TrackingHud())
    val trackingHud: StateFlow<TrackingHud> = _trackingHud.asStateFlow()
    val isFeedRecovering: Boolean get() = recoveryState.value.isRecovering
    val isTrackingActive: Boolean get() = _trackingHud.value.isTracking
    /** iOS: the focus key shows once the focus point is off centre or Deep Track runs. */
    val isFocusResetAvailable: Boolean
        get() = _focusPoint.value.let { (x, y) -> FocusResetPolicy.isAvailable(x.toDouble(), y.toDouble(), isTrackingActive) }
    // AE / AWB lock pin the camera's applied Auto values as Manual (core `AutoExposureLock`). The Luna
    // reports only its exposure and WB settings, never the applied Auto ISO, shutter or Kelvin, so there
    // is nothing to pin: the long-press, the AE-L row and the AWB Lock row stay hidden.
    val aeLock: StateFlow<AutoExposureLock?> = MutableStateFlow<AutoExposureLock?>(null).asStateFlow()
    val awbLockKelvin: StateFlow<Int?> = MutableStateFlow<Int?>(null).asStateFlow()
    val canLockAutoExposure: Boolean get() = false
    fun lockAutoExposure(): Boolean = false
    fun unlockAutoExposure() = Unit
    fun autoWhiteBalanceLock(status: CameraStatus = _status.value): Pair<Int, Int>? = null
    fun lockAutoWhiteBalance() = Unit

    // Serialize source replacement/probe reset with queued frame admission.
    private val recoveryFrameLock = Any()
    @Volatile private var lastAccessUnitAt: Long? = null
    @Volatile private var lastFrameGeneration: Long? = null
    /** Current accepted encoded-frame source, read directly rather than from a coalesced UI projection. */
    val faceReadbackStreamGeneration: com.opencapture.opencine.core.StreamGeneration?
        get() {
            val source = backend.frameConnectionGeneration ?: return null
            return com.opencapture.opencine.core.StreamGeneration(source).takeIf { lastFrameGeneration == source }
        }
    @Volatile private var sourceProbeStartedAt: Long? = null
    // The recovering camera and the frame source its current attempt opened.
    private var recoveryCameraId: String? = null
    @Volatile private var recoverySource: Long? = null
    /** The shared recovery episode; transport, decoder and the picture gates stay here. */
    private val recoveryEpisode =
        SessionRecoveryEpisode(
            scope = scope,
            port = RecoveryPort(),
            attemptDeadline = LUNA_RECOVERY_ATTEMPT_DEADLINE,
            timing = SessionRecoveryEpisode.Timing(SystemClock::elapsedRealtime),
        ) { applyRecovery(it) }
    internal val isSessionRecoveryRunning: Boolean get() = recoveryEpisode.isRunning

    init {
        scope.launch {
            backend.snapshot.collect { value ->
                value.batteryPercent?.let { _status.value = _status.value.copy(batteryPercent = it) }
            }
        }
        controls?.let { link ->
            scope.launch { link.readout.collect(::applyReadout) }
            scope.launch { link.trackFrames.collect { frame -> if (acceptsTrackFrame(frame)) tracking.ingest(frame) } }
            scope.launch { link.notices.collect(::applyNotice) }
            // Re-apply every second: the REC timer ticks and settled pins fall back to the camera's value.
            scope.launch { while (isActive) { delay(1_000); applyReadout(lastReadout) } }
        }
        scope.launch {
            backend.connected.collect { value ->
                connectedCamera = value?.let(::displayCamera)
                joinedSSID = backend.joinedSSID.value
            }
        }
        scope.launch {
            backend.phase.collect { value ->
                if (value != ConnectionPhase.IDLE && value != ConnectionPhase.SCANNING && value != ConnectionPhase.FAILED && !incidentSessionActive) beginFeedIncidentSession()
                if (value == ConnectionPhase.IDLE) releaseReportingCameraPath()
                else if (value != ConnectionPhase.SCANNING && value != ConnectionPhase.FAILED) holdReportingCameraPath()
                if (value != ConnectionPhase.LIVE) { cancelProgrammedMove(); retireNativeCaptureRequests() }
                when (value) {
                    ConnectionPhase.LIVE -> {
                        holdsMonitor = true; resetFrameClock()
                        startGimbalAnglePoll()
                        // IA-366: a live picture reached outside the bounded episode (a resume
                        // reconnect) clears the waiting "Camera disconnected" card, as the
                        // phase-driven baseline did. A running episode publishes its own idle.
                        if (retiresRecoveryOnLive(recoveryEpisode.isRunning)) retireRecovery()
                    }
                    ConnectionPhase.FAILED -> {
                        resetFrameClock(); stopGimbalAngle()
                        if (holdsMonitor) beginSessionRecovery()
                    }
                    ConnectionPhase.IDLE -> {
                        endFeedIncidentSession()
                        resetFrameClock(); stopGimbalAngle()
                        faceAFArmJob?.cancel(); faceAFArmJob = null; _faceAFArmed.value = false; publishFaceDetectWanted()
                        retireRecovery()
                        holdsMonitor = false
                        pins.clear(); recordStartedAt = null; _controlBusy.value = false
                    }
                    else -> Unit
                }
            }
        }
        scope.launch {
            while (isActive) {
                delay(1_000)
                publishFeedIncidentSnapshot()
            }
        }
        scope.launch(Dispatchers.Default) {
            backend.frames.collect { frame ->
                synchronized(recoveryFrameLock) {
                    val generation = backend.frameConnectionGeneration
                    if (generation != null && frame.connectionGeneration != generation) return@synchronized
                    lastAccessUnitAt = SystemClock.elapsedRealtime()
                    lastFrameGeneration = frame.connectionGeneration
                    noteFrameClock(frame.timestampMicros)
                    videoPackets += 1
                    accessUnits += 1
                    if (decoder.decode(frame.annexB)) { framesEnqueued += 1; hasVideoFormat = true }
                }
            }
        }
    }

    private fun displayCamera(value: CameraIdentity): FoundCamera {
        val facts = controlCapabilities()
        return FoundCamera(
            value.id, value.id, value.advertisedName,
            CameraModel(
                name = value.modelName, datalinkPort = 0, tcpPoke = false, verified = true, pairingToken = "luna",
                family = "generic", supportsTapFocus = facts.tapFocus.isOffered, supportsFocusMode = facts.focus.isOffered,
                usesCapturedLiveEnable = false, zoomStops = lunaZoomStops(), hasGimbal = facts.gimbal.isOffered,
                supportsZoom = facts.zoom.isOffered, sendsLiveViewPrepare = false, supportsAperture = facts.iris.isOffered,
                captureProfile = LunaCameraSession.CAPTURE_PROFILE.copy(labels = profile.labels,
                    zoom = CameraZoomProfile(stops = lunaZoomStops()), looks = LunaCameraLUTProfile.value),
            ),
            null,
        )
    }

    private fun lunaZoomStops(): List<Double> {
        val ceiling = controls?.zoomRange?.endInclusive ?: 1.0
        val stops = LUNA_ZOOM_CHIPS.filter { it <= ceiling }.toMutableList()
        if (stops.isEmpty()) stops += 1.0
        if (ceiling > stops.last() + 0.5) stops += ceiling
        return stops
    }

    // Connection.
    fun startScan() = backend.startScan()

    /**
     * The backend as the Luna integration's port (SHELL-02): the integration drives discovery and
     * each attempt; this session follows it with a fresh picture. The connected camera's Core
     * session reaches [control] through the app's shell (SHELL-03), never from here. `null` for a
     * backend that is not a Luna port (the debug local replay).
     */
    val lunaPort: LunaConnectPort? = (backend as? LunaConnectPort)?.let { port ->
        object : LunaConnectPort by port {
            override fun openSession(): com.opencapture.opencine.core.CameraSession = port.openSession().also {
                (it as? LunaCameraSession)?.configureShutter(if (OperatorPrefs.shutterUsesAngle(appContext))
                    com.opencapture.opencine.media.HostShutterPresentation.EMULATED_ANGLE
                    else com.opencapture.opencine.media.HostShutterPresentation.CAMERA_VALUE)
            }
            override fun connect(id: String) {
                holdReportingCameraPath()
                retireRecovery()
                cancelProgrammedMove()
                synchronized(recoveryFrameLock) {
                    decoder.reset(); videoPackets = 0; hasVideoFormat = false
                    port.connect(id)
                }
            }
        }
    }

    fun configureShutterPresentation(usesAngle: Boolean) {
        (control.state.value.session as? LunaCameraSession)?.configureShutter(if (usesAngle)
            com.opencapture.opencine.media.HostShutterPresentation.EMULATED_ANGLE
            else com.opencapture.opencine.media.HostShutterPresentation.CAMERA_VALUE)
    }

    /**
     * What the monitor lays out: the Luna session's projection (iOS `LunaCameraSession.layout`).
     * No session: the pre-connection model's view over [base] (Luna's static profile).
     */
    fun layout(base: MonitorLayoutCapabilities): MonitorLayoutCapabilities =
        com.opencapture.opencine.vocabulary.MonitorLayoutCapabilities(controlCapabilities(), base)

    /**
     * The Luna integration's one control model while a Luna session is connected, else the shared
     * pre-connection rule over Luna's static profile (iOS `CameraSession.controlCapabilities`).
     */
    fun controlCapabilities(): com.opencapture.opencine.vocabulary.ControlCapabilities {
        val state = control.state.value
        (state.session as? LunaCameraSession)?.let { return it.controlCapabilities() }
        if (backend.connected.value != null) return LunaCameraSession.controlCapabilities(
            state.snapshot?.capabilities ?: com.opencapture.opencine.core.CapabilitySnapshot(), backend.capabilities)
        return com.opencapture.opencine.vocabulary.ControlCapabilities.beforeConnection(
            LunaCameraSession.CAPTURE_PROFILE, LunaCameraSession.MOTION)
    }

    fun attachSurface(surface: Surface?) = decoder.attachSurface(surface)
    fun disconnect() {
        retireNativeCaptureRequests()
        endFeedIncidentSession()
        retireRecovery()
        releaseReportingCameraPath()
        cancelProgrammedMove()
        synchronized(recoveryFrameLock) { backend.disconnect(); decoder.reset() }
        holdsMonitor = false; hasVideoFormat = false
        tracking.clear()
    }
    fun close() {
        if (closed) return
        retireNativeCaptureRequests()
        endFeedIncidentSession()
        releaseReportingCameraPath()
        closed = true
        retireRecovery()
        cancelProgrammedMove()
        synchronized(recoveryFrameLock) { backend.close(); decoder.reset() }
        scope.cancel()
    }
    fun noteSceneBecameInactive() {
        programSceneActive = false; cancelProgrammedMove(); backend.sceneActive(false)
        feedIncidents?.recordBreadcrumb(FeedIncidentBreadcrumb(SystemClock.elapsedRealtime() / 1_000.0, FeedIncidentBreadcrumbKind.SCENE_ACTIVITY, "inactive"))
    }
    fun noteSceneBecameActive() {
        programSceneActive = true
        feedIncidents?.recordBreadcrumb(FeedIncidentBreadcrumb(SystemClock.elapsedRealtime() / 1_000.0, FeedIncidentBreadcrumbKind.SCENE_ACTIVITY, "active"))
        // The bounded recovery episode already owns reconnect while the link is failed.
        if (!recoveryEpisode.isRunning) backend.sceneActive(true)
    }
    internal fun hasRecoveryPicture(startedAt: Long, generation: Long? = backend.frameConnectionGeneration): Boolean {
        val source = generation ?: return false
        if (backend.frameConnectionGeneration != source || lastFrameGeneration != source) return false
        val now = SystemClock.elapsedRealtime()
        val admitted = decoder.lastDecoderAcceptedAt ?: return false
        if (admitted < startedAt || now - admitted !in 0 until 2_000) return false
        // C2 surface output may not emit an output callback. Its fresh codec-stamped
        // presentation still proves a decoded picture after this source's input admission.
        if (decoder.decoderOutputExpected) {
            val output = decoder.lastDecoderOutputAt ?: return false
            if (output < startedAt || now - output !in 0 until 2_000) return false
        }
        return RecoveryPictureProof.isFresh(startedAt, now, decoder.lastPresentedAt, lastAccessUnitAt)
    }
    /** iOS `retrySessionRecovery`: the operator starts a fresh bounded run. */
    fun retrySessionRecovery() {
        recoveryEpisode.resetStorm()
        retireRecovery()
        beginSessionRecovery(SessionRecoveryTrigger.OPERATOR_RETRY)
    }
    private fun retireRecovery() = recoveryEpisode.cancel()
    /**
     * iOS `beginSessionRecovery`: a live drop keeps the monitor on the last frame while the shared
     * episode reconnects through the backend's BLE-first path, retrying at once then 0.5 s to 8 s
     * jittered, at most 8 attempts within 180 s; then the Recovery card waits for the operator.
     */
    private fun beginSessionRecovery(trigger: SessionRecoveryTrigger = SessionRecoveryTrigger.DATALINK_LOST) {
        val id = backend.connected.value?.id ?: return
        val previousTarget = recoveryCameraId
        recoveryCameraId = id
        if (!recoveryEpisode.begin(id, trigger, "link failed")) {
            if (!_recoveryState.value.isRecovering) recoveryCameraId = previousTarget
            return
        }
        if (_recoveryState.value !is SessionRecoveryUi.Retrying) return
        if (phase == ConnectionPhase.FAILED) feedIncidents?.noteUnexpectedDisconnect(SystemClock.elapsedRealtime() / 1_000.0)
        Log.i("OpenInstaCine", "session: drop, bounded recovery")
    }
    private fun applyRecovery(snapshot: SessionRecoveryEpisode.Snapshot) {
        val previous = _recoveryState.value
        _recoveryState.value = snapshot.state
        if (snapshot.state is SessionRecoveryUi.WaitingForOperator && previous !is SessionRecoveryUi.WaitingForOperator) {
            feedIncidents?.noteExhausted(SystemClock.elapsedRealtime() / 1_000.0)
        }
        // A recovered episode keeps its target; a local cancel clears or keeps the hold.
        if (previous is SessionRecoveryUi.Retrying && snapshot.state == SessionRecoveryUi.Idle &&
            snapshot.targetId != null && !snapshot.holdsPicture
        ) {
            Log.i("OpenInstaCine", "session: recovered picture after ${previous.attempt - 1} failed attempt(s)")
        }
    }
    /** The Luna backend as the shared episode's transport. */
    private inner class RecoveryPort : SessionRecoveryEpisode.Port {
        override fun observe(): SessionRecoveryEpisode.Observation {
            val target = recoveryCameraId
            val source = recoverySource
            val live = phase == ConnectionPhase.LIVE
            // Only a decoded picture of this attempt's source counts (codec admission and output).
            val pictured = live && source != null && synchronized(recoveryFrameLock) {
                sourceProbeStartedAt?.let { hasRecoveryPicture(it, source) } == true
            }
            return SessionRecoveryEpisode.Observation(
                // Idle is the operator's or the app's disconnect: the episode ends without a word.
                ownsConnection = !closed && target != null && phase != ConnectionPhase.IDLE &&
                    backend.connected.value?.id == target,
                progress = when {
                    source != null && backend.frameConnectionGeneration != source ->
                        SessionRecoveryEpisode.Progress.SUPERSEDED
                    phase == ConnectionPhase.FAILED -> SessionRecoveryEpisode.Progress.FAILED
                    else -> SessionRecoveryEpisode.Progress.RUNNING
                },
                stage = if (live) SessionRecoveryEpisode.Stage.LIVE else SessionRecoveryEpisode.Stage.CONNECTING,
                sourceAtMs = if (pictured) lastAccessUnitAt else null,
                presentedAtMs = if (pictured) decoder.lastPresentedAt else null,
            )
        }

        override fun cleanup(kind: SessionRecoveryEpisode.Cleanup, attempt: SessionRecoveryEpisode.Attempt) {
            if (kind == SessionRecoveryEpisode.Cleanup.INITIAL_DROP) recoverySource = null
        }

        override suspend fun connect(attempt: SessionRecoveryEpisode.Attempt): Boolean {
            val id = recoveryCameraId ?: return false
            recoverySource = synchronized(recoveryFrameLock) {
                backend.connect(id)
                backend.frameConnectionGeneration
            }
            withContext(Dispatchers.IO) {
                synchronized(recoveryFrameLock) {
                    decoder.prepareAfterForeground()
                    lastAccessUnitAt = null; lastFrameGeneration = null
                    sourceProbeStartedAt = decoder.beginPresentationProbe()
                }
            }
            attempt.checkContinuation()
            // The backend may still report the drop's failure for a moment after the call.
            kotlinx.coroutines.withTimeoutOrNull(2_000) { backend.phase.first { it != ConnectionPhase.FAILED } }
            return true
        }
    }
    fun abandonRecoveryToMenu() = disconnect()

    private fun beginFeedIncidentSession() {
        incidentSessionActive = true
        incidentRateSampler.reset()
        feedIncidents = incidentSessionSink.beginBoundSession(
            AppDiagnostics.incidents.sessionContext(cameraFamily = "luna"))
    }

    private fun endFeedIncidentSession() {
        if (!incidentSessionActive) return
        incidentSessionActive = false
        incidentRateSampler.reset()
        val incident = feedIncidents
        feedIncidents = null
        incident?.endSession(SystemClock.elapsedRealtime() / 1_000.0)
    }

    /** Diagnostic snapshot from actual AU admission, native decoder and present clocks. */
    internal fun feedIncidentSnapshot(nowMs: Long = SystemClock.elapsedRealtime()): FeedIncidentSnapshot = synchronized(recoveryFrameLock) {
        val now = nowMs / 1_000.0
        val generation = backend.frameConnectionGeneration
        val pipeline = cadence.snapshot()
        val rates = incidentRateSampler.sample(now, FeedIncidentStageCounts(
            accessUnit = accessUnits.toLong(), decodeAccept = decoder.framesEnqueued.get().toLong(),
            decodedOutput = pipeline.counts.getValue(LivePipelineCadence.Stage.OUTPUT),
            present = decoder.framesPresented.get().toLong()),
            epoch = FeedIncidentCounterEpoch(decoder.errorLifetime.generation.toLong(), generation))
        fun age(at: Long?): Double? = FeedIncidentRateSampler.ageMilliseconds(at, nowMs)
        fun sourceAge(at: Long?): Double? = at?.takeIf {
            sourceProbeStartedAt?.let { started -> it >= started } != false
        }?.let(::age)
        val currentSource = generation != null && lastFrameGeneration == generation
        val error = decoder.errorLifetime.lastError?.takeIf {
            sourceProbeStartedAt?.let { started -> it.atElapsedMs >= started } != false
        }
        FeedIncidentSnapshot(
            monotonicNow = now, wallClockMs = System.currentTimeMillis(),
            // Luna exposes AUs, not transport packet/ACK/queue counters; do not relabel them.
            rates = rates,
            ages = FeedIncidentAges(accessUnitAge = if (currentSource) age(lastAccessUnitAt) else null,
                decodeAcceptAge = if (currentSource) sourceAge(decoder.lastDecoderAcceptedAt) else null,
                decodedOutputAge = if (currentSource) sourceAge(decoder.lastDecoderOutputAt) else null,
                presentAge = if (currentSource) sourceAge(decoder.lastPresentedAt) else null),
            decoder = decoder.incidentDecoder(nowElapsedMs = nowMs, generation = decoder.errorLifetime.generation,
                codec = error?.codec ?: "unknown", errorNotBefore = sourceProbeStartedAt,
                outputAge = if (currentSource) sourceAge(decoder.lastDecoderOutputAt) else null,
                receivedIrap = decoder.lastIrapAt != null),
            lifecycle = FeedIncidentLifecycle(foreground = programSceneActive, playbackActive = isBrowsingMedia,
                connected = backend.connected.value != null && phase != ConnectionPhase.IDLE,
                liveEstablished = decoder.lastPresentedAt != null, sceneActive = programSceneActive,
                thermalState = "unknown", assistState = "unknown",
                outputObservable = decoder.decoderOutputExpected, presentationExpected = decoder.isPresentationReady),
        )
    }

    private fun publishFeedIncidentSnapshot() {
        if (!incidentSessionActive || closed) return
        val incident = feedIncidents ?: return
        val snapshot = feedIncidentSnapshot()
        incident.noteDecoderGeneration(snapshot.decoder.generation)
        incident.ingestSnapshot(snapshot)
    }

    // Status mapping (Luna readout to the shared CameraStatus), iOS `applyDeviceStatus`/`applySettings`/`applyCapture`.
    private fun applyReadout(readout: CameraReadout) {
        lastReadout = readout
        _nativeFormats.value = readout.recordFormats
        if (nativeFormatPin?.value?.expected?.let { it !in readout.recordFormats } == true) nativeFormatPin = null
        val nativeNow = nativePinNow()
        val (format, formatPin) = nativeReadout(nativeFormatPin, readout.recordFormat, nativeNow)
        val (color, colorPin) = nativeReadout(nativeColorPin, readout.color, nativeNow)
        nativeFormatPin = formatPin; nativeColorPin = colorPin
        _nativeFormat.value = format
        _nativeColor.value = color
        val now = SystemClock.elapsedRealtime()
        var next = LunaShellMapping.applyDevice(readout, _status.value, pins, now)
        val (settled, table) = LunaShellMapping.applySettings(readout, next, pins, now)
        next = settled
        formatTable = table
        readout.gimbalMode?.let(LunaShellMapping::gimbalMode)?.let { mode ->
            if (pins::gimbalMode.hold(mode, now) == null) _gimbalMode.value = mode
        }
        readout.gimbalSpeed?.let(LunaShellMapping::gimbalSpeed)?.let { speed ->
            if (pins::gimbalSpeed.hold(speed, now) == null) _gimbalSpeed.value = speed
        }
        _faceMetering.value = readout.faceMetering?.let { pins::faceMetering.hold(it, now) ?: it }
        readout.zoom?.let { if (zoomTarget == null && zoomPinchPreview == null) _zoomReadout.value = it }
        // ISO, shutter, WB and recording itself come from the shared control model; the readout keeps the REC timer.
        next = projectControls(next)
        val recording = readout.recording == true
        if (recording && recordStartedAt == null) recordStartedAt = now - readout.captureSeconds * 1_000L
        if (!recording) recordStartedAt = null
        val elapsed = if (recording) maxOf(readout.captureSeconds, recordStartedAt?.let { ((now - it) / 1_000).toInt() } ?: 0) else 0
        next = next.copy(recordElapsedSec = elapsed)
        _status.value = next
        if (_controlBusy.value && !pins.photoInFlight) _controlBusy.value = false
        publishFaceDetectWanted()
    }

    private fun resetFrameClock() {
        frameTimecode.reset()
    }

    /** [stampMicros]: the frame's camera clock (Luna: its u64 ms header stamp, in microseconds). */
    private fun noteFrameClock(stampMicros: Long) {
        // The HUD shows HH:MM:SS: published once per displayed second.
        val timecode = frameTimecode.note(stampMicros / 1_000, System.currentTimeMillis(), java.util.TimeZone.getDefault())
            ?: return
        (control.state.value.session as? LunaCameraSession)?.ingest(timecode)
    }

    private fun canSendControl(): Boolean {
        if (phase == ConnectionPhase.LIVE && can(CameraCapability.CAMERA_SETTINGS)) return true
        presentControlNote("Connect the camera to use its controls.")
        return false
    }

    /** One Luna request off the main flow. Failure reverts through [onFail]; success re-reads settings. */
    private fun sendControl(
        name: String,
        refresh: Boolean = true,
        onFail: () -> Unit = {},
        onSuccess: () -> Unit = {},
        admission: () -> Boolean = { true },
        request: suspend CameraControls.() -> Boolean,
    ) {
        val link = controls ?: return
        scope.launch {
            if (!admission()) return@launch
            val applied = link.request()
            if (!admission()) return@launch
            if (applied) {
                onSuccess()
                if (refresh && admission()) link.requestSettingsRefresh()
            } else {
                presentControlNote("$name was not applied by the camera.")
                onFail()
            }
        }
    }

    /** Coalesces rapid drum edits into one send per key per ~120 ms, latest wins (iOS `LunaExposureCoalescer`). */
    private val coalesced = HashMap<String, () -> Unit>()
    private fun coalesce(key: String, work: () -> Unit) {
        val scheduled = coalesced.containsKey(key)
        coalesced[key] = work
        if (scheduled) return
        scope.launch { delay(120); coalesced.remove(key)?.invoke() }
    }

    // Record and photo. Record never lies: the lamp holds busy until the camera reports the outcome.
    // The shared model resolves start or stop from the session's snapshot; unknown sends nothing.
    fun pressRecord() {
        if (canSendControl()) control.record(null)
    }

    /** Rec lamp: a still in Photo, otherwise start/stop video (timelapse modes record too). */
    fun pressShutter() {
        if (!_status.value.isPhoto) return pressRecord()
        if (!canSendControl()) return
        _controlBusy.value = true
        pins.photoInFlight = true
        presentControlNote("Photo")
        sendControl(
            "Photo", refresh = false,
            onFail = { pins.photoInFlight = false; _controlBusy.value = false },
            onSuccess = { pins.photoInFlight = false; _controlBusy.value = false; _mediaCaptured.tryEmit(Unit) },
        ) { takePhoto() }
    }

    fun setShootingMode(raw: Int) {
        if (!canSendControl()) return
        val mode = LunaShellMapping.cameraShootingMode(raw) ?: return
        val previous = _status.value
        if (previous.isRecording) return presentControlNote(ControlHud.RECORDING_COLOR_LOCK_NOTE)
        pins.shootingMode = pin(raw, SystemClock.elapsedRealtime(), 3_000)
        pins.format = null
        _status.value = if (previous.shootingMode != raw) previous.clearedModeDependentCapabilities().copy(shootingMode = raw) else previous
        sendControl(
            CameraCommands.shootingModeLabel(raw, profile = profile.labels).orEmpty(), refresh = false,
            onFail = { pins.shootingMode = null; _status.value = _status.value.copy(shootingMode = previous.shootingMode) },
        ) { setShootingMode(mode) }
    }

    // Exposure: ISO and shutter go to the Core session, which owns Luna's one exposure message.
    fun setIsoIndex(index: Int) {
        if (!canSendControl()) return
        val iso = if (index == 0) ISOValue.Auto else ISOValue.Manual(CameraCommands.isoValue(index) ?: return)
        control.set(SettingValue.Iso(iso), "ISO ${CameraCommands.isoLabel(index)}")
    }

    fun setShutterDenom(denom: Int) {
        if (!canSendControl() || denom <= 0) return
        control.set(SettingValue.Shutter(ShutterValue.Duration(Rational(1, denom))), "1/$denom")
    }

    /** Only explicit angle choices write the saved intent; delayed telemetry never does. */
    fun setShutterAngle(degrees: Double) {
        if (!canSendControl() || _status.value.isPhoto) return
        val angle = ShutterAngle.nearestDegrees(degrees)
        OperatorPrefs.setShutterAngleDegrees(appContext, angle)
        val current = _status.value
        setShutterDenom(ShutterAngle.denom(angle, current.fps, current.availableShutterDenoms))
    }

    fun setExpoMode(mode: Int) {
        if (!canSendControl()) return
        if (mode == CameraCommands.EXPO_AUTO) {
            control.set(SettingValue.Iso(ISOValue.Auto), "Auto exposure")
            return control.set(SettingValue.Shutter(ShutterValue.Auto), "Auto exposure")
        }
        // Manual needs a shutter: keep the current one, else the nearest offered 180 degrees.
        val status = _status.value
        val wanted = status.shutterDenom.takeIf { it > 0 } ?: (maxOf(status.fps, 25) * 2)
        val denom = status.availableShutterDenoms.minByOrNull { abs(it - wanted) } ?: wanted
        control.set(SettingValue.Shutter(ShutterValue.Duration(Rational(1, denom))), "Manual exposure")
    }

    fun setEv(thirds: Int) {
        if (!canSendControl()) return
        val ev = EvComp.fromThirds(thirds)
        pins.ev = pin(ev.rawValue, SystemClock.elapsedRealtime())
        _status.value = _status.value.copy(evComp = ev.rawValue)
        coalesce("ev") { sendControl("EV ${ev.label}", onFail = { pins.ev = null }) { setExposureBias(ev.thirds) } }
    }

    // Face priority needs on-phone face detection feeding EV; the Luna shell does not run it yet.
    fun setFacePriorityEnabled(on: Boolean) { if (on) unavailable("Face priority") }
    /** Luna's ISO ceiling is not an operator setting in the official app. */
    fun setIsoLimit(raw: Int) = presentControlNote("Auto ISO ceiling is managed by the camera.")
    fun setApertureStrategy(raw: Int) { presentControlNote("Aperture control unavailable") }
    fun getIsoLimit() = Unit
    suspend fun refreshIsoLimit(): Boolean = false

    // Zoom (1x to the camera's reported ceiling, 15x on Luna Ultra).
    fun zoomCycleFrom(): Double = zoomPinchPreview ?: zoomTarget ?: _zoomReadout.value
    fun zoomStops(): List<Double> = connectedCamera?.model?.zoomStops ?: listOf(1.0)
    fun zoomMax(): Double = zoomStops().lastOrNull() ?: 1.0
    fun zoomNextJump(): Double = CamFov.nextJump(zoomCycleFrom(), zoomStops())
    fun setZoomLens(position: Int) = Unit
    fun setZoom(factor: Double) {
        if (!supportsZoom) return
        val range = controls?.zoomRange ?: return
        val target = factor.coerceIn(range.start, range.endInclusive)
        zoomTarget = target
        _zoomReadout.value = target
        scope.launch {
            val ok = controls.setZoom(target)
            if (zoomTarget == target) zoomTarget = null
            if (!ok) presentControlNote("Zoom did not reach the camera.")
        }
    }
    fun setZoomSlider(factor: Double) = setZoom(factor)
    fun setZoomSlew(value: Int) = Unit
    fun setZoomStop() = Unit
    fun updateZoomPinch(magnification: Double) {
        if (!supportsZoom) return
        if (!_zoomPinching.value) { zoomPinchBase = _zoomReadout.value; _zoomPinching.value = true }
        zoomPinchPreview = (zoomPinchBase * magnification).coerceIn(1.0, zoomMax())
    }
    fun endZoomPinch() {
        val preview = zoomPinchPreview
        zoomPinchPreview = null
        _zoomPinching.value = false
        if (preview != null) setZoom(preview)
    }

    // Gimbal.
    fun performGimbalDoubleTap() = when (gimbalDoubleTap) {
        GimbalDoubleTap.RECENTER -> recenterGimbal()
        GimbalDoubleTap.LEVEL -> levelGimbalToWorld()
    }
    /** iOS `levelGimbalToWorld`: tilt the head to the horizon, keeping yaw; one refine pass from still. */
    fun levelGimbalToWorld(refine: Boolean = true) {
        val angle = freshGimbalAngle(500)
        val head = controls?.gimbalHeadPitch
        if (angle == null || head == null) return presentControlNote(WorldLevelSnap.NO_LEVEL_DATA)
        val target = LunaGimbalAim.levelTarget(angle, head, _zoomReadout.value)
        Log.i("OpenInstaCine", "gimbal-level: angle=%.1f,%.1f head=%.1f target=%.1f".format(Locale.US, angle.pitch, angle.yaw, head, target.pitchDeg))
        aimGimbal(target)
        if (!refine) return
        // The IMU pitch filter lags a recent move by about 0.5 deg: correct once from still.
        scope.launch {
            delay(2_500)
            val pitch = controls?.gimbalHeadPitch ?: return@launch
            if (aimJob?.isActive != true && !motion.isHeld && !programmedMove.state.value.progress.running && abs(pitch) > 0.3) {
                levelGimbalToWorld(refine = false)
            }
        }
    }

    // Absolute angle: GET_ANGLE every 100 ms while live (iOS `startGimbalAnglePoll`).
    private var gimbalAngle: Pair<CameraGimbalAngle, Long>? = null
    private var anglePollJob: Job? = null
    private var aimJob: Job? = null
    private fun freshGimbalAngle(maxAgeMs: Long) =
        gimbalAngle?.takeIf { SystemClock.elapsedRealtime() - it.second <= maxAgeMs }?.first
    private fun startGimbalAnglePoll() {
        if (!can(CameraCapability.GIMBAL)) return
        anglePollJob?.cancel()
        anglePollJob = scope.launch {
            while (isActive) {
                motion.readAngle()?.let { gimbalAngle = it to SystemClock.elapsedRealtime() }
                delay(100)
            }
        }
    }
    private fun stopGimbalAngle() {
        cancelProgrammedMove(); aimJob?.cancel()
        anglePollJob?.cancel(); anglePollJob = null; gimbalAngle = null
    }
    private fun sendGimbalAngle(target: GimbalWaypoint) {
        scope.launch { motion.aim(target) }
    }
    /** iOS `aimGimbal`: one SET_ANGLE; the aim ends once GET_ANGLE reads within 0.5 deg, or after 8 s. */
    private fun aimGimbal(target: GimbalWaypoint) {
        if (!canSetGimbalConfiguration() || motion.isHeld || programmedMove.state.value.progress.running) return
        aimJob?.cancel()
        aimJob = scope.launch {
            sendGimbalAngle(target)
            val started = SystemClock.elapsedRealtime()
            while (isActive && canSetGimbalConfiguration() && !motion.isHeld) {
                val elapsed = SystemClock.elapsedRealtime() - started
                if (elapsed > 8_000) break
                val reading = gimbalAngle
                if (elapsed > 300 && reading != null && reading.second > started + 200 &&
                    LunaMotionService.hasReached(reading.first, target)
                ) break
                delay(33)
            }
        }
    }
    fun recenterGimbal() {
        if (!hasGimbal) return
        aimJob?.cancel()
        scope.launch { if (!motion.recenter()) presentControlNote("Recenter did not reach the camera.") }
    }
    fun flipGimbal() {
        if (!hasGimbal) return
        scope.launch { if (!motion.flip()) presentControlNote("Flip did not reach the camera.") }
    }
    fun updateGimbalStick(
        x: Float,
        y: Float,
        sensitivity: Int = CameraCommands.GIMBAL_STICK_DEFAULT_SENSITIVITY,
        assistMirror: Boolean = false,
        linear: Boolean = false,
        mapping: CameraCommands.VirtualJoystickMapping = CameraCommands.VirtualJoystickMapping.DEFAULT,
    ) {
        if (!hasGimbal) return
        // The operator's stick always wins over an aim or a programmed move.
        if (x != 0f || y != 0f) {
            aimJob?.cancel()
            if (programmedMove.state.value.progress.running) cancelProgrammedMove()
        }
        // Same shaping as the iOS Luna session: deadzone, ease-in curve, sensitivity scale.
        val dead = if (linear) CameraCommands.GIMBAL_STICK_DEADZONE else mapping.deadzone
        val still = hypot(x.toDouble(), y.toDouble()) < dead
        val scale = minOf(1.0, sensitivity.toDouble() / CameraCommands.GIMBAL_STICK_DEFAULT_SENSITIVITY)
        fun shaped(v: Double) = (if (linear) v else v * abs(v)) * scale
        val pan = if (still) 0.0 else if (assistMirror) -x.toDouble() else x.toDouble()
        val tilt = if (still) 0.0 else y.toDouble()
        motion.hold(shaped(pan), shaped(tilt))
    }
    fun endGimbalStick() {
        motion.endHold()
        if (hasGimbal) scope.launch { motion.release() }
    }
    private fun canSetGimbalConfiguration() = hasGimbal && phase == ConnectionPhase.LIVE && !isBrowsingMedia
    fun setGimbalMode(mode: GimbalMode) {
        if (!canSetGimbalConfiguration()) return
        val previous = _gimbalMode.value
        pins.gimbalMode = pin(mode, SystemClock.elapsedRealtime(), 3_000)
        _gimbalMode.value = mode
        sendControl("Gimbal ${mode.label(profile.labels)}", onFail = { pins.gimbalMode = null; _gimbalMode.value = previous }) {
            setGimbalMode(LunaShellMapping.cameraGimbalMode(mode))
        }
    }
    fun setGimbalSpeed(speed: GimbalSpeed) {
        if (!canSetGimbalConfiguration()) return
        val previous = _gimbalSpeed.value
        pins.gimbalSpeed = pin(speed, SystemClock.elapsedRealtime(), 3_000)
        _gimbalSpeed.value = speed
        sendControl("Gimbal speed ${speed.label}", onFail = { pins.gimbalSpeed = null; _gimbalSpeed.value = previous }) {
            setGimbalSpeed(LunaShellMapping.cameraGimbalSpeed(speed))
        }
    }
    fun setGimbalWaypoint(slot: GimbalWaypointSlot) {
        if (!hasGimbal) return
        if (programmedMove.state.value.progress.running || motion.isHeld) return presentControlNote(GimbalHudCopy.HOLD_STILL)
        val angle = freshGimbalAngle(300) ?: return presentControlNote(GimbalHudCopy.POSE_NOT_READY)
        _gimbalProgram.update { it.withPoint(slot, LunaGimbalAim.waypoint(angle, _zoomReadout.value)) }
    }
    fun clearGimbalWaypoint(slot: GimbalWaypointSlot) {
        cancelProgrammedMove()
        _gimbalProgram.update { it.withPoint(slot, null) }
    }
    fun setGimbalLegDuration(ab: Double? = null, bc: Double? = null) {
        if (programmedMove.state.value.progress.running) cancelProgrammedMove()
        _gimbalProgram.update { program ->
            var next = program
            if (ab != null) next = next.copy(durationAB = GimbalProgram.snapDuration(maxOf(ab, GimbalProgram.minTravelDuration(next.a, next.b))))
            if (bc != null) next = next.copy(durationBC = GimbalProgram.snapDuration(maxOf(bc, GimbalProgram.minTravelDuration(next.b, next.c))))
            next
        }
    }
    fun setGimbalSmoothness(value: Double) {
        if (!value.isFinite()) return
        cancelProgrammedMove()
        _gimbalProgram.update { it.copy(smoothness = value.coerceIn(0.0, 1.0)) }
    }
    fun setGimbalLoop(enabled: Boolean) {
        cancelProgrammedMove()
        _gimbalProgram.update { it.copy(loop = enabled) }
    }
    fun clearGimbalProgram() {
        cancelProgrammedMove()
        _gimbalProgram.update { GimbalProgram(durationAB = it.durationAB, durationBC = it.durationBC) }
    }

    /** iOS runProgrammedMove: shared timeline/scheduler, captured source and integration-owned wire values. */
    fun runProgrammedMove() {
        if (!hasGimbal || !programSceneActive) return
        if (programmedMove.state.value.progress.running) return cancelProgrammedMove()
        programmedZoomUnavailableReason()?.let { return presentControlNote(it) }
        val take = _gimbalProgram.value
        if (!canRunProgrammedMove || gimbalAngle == null) {
            return presentControlNote(if (take.canRun) GimbalHudCopy.POSE_NOT_READY else GimbalHudCopy.NEED_AB)
        }
        val session = control.state.value.session as? LunaCameraSession
            ?: return presentControlNote("Connect the camera to use its controls.")
        val epoch = session.snapshots.value.epoch
        val service = LunaMotionService.boundTo(session, scope)
            ?: return presentControlNote("Connect the camera to use its controls.")
        val source = MotionProgramSession.Source(service) {
            val snapshot = session.snapshots.value
            control.state.value.session === session && phase == ConnectionPhase.LIVE && programSceneActive &&
                snapshot.epoch == epoch && snapshot.connection == com.opencapture.opencine.core.ConnectionState.Ready &&
                snapshot.authority == com.opencapture.opencine.core.ControlAuthority.Owner
        }
        _controlNote.value = null
        aimJob?.cancel()
        if (motion.isHeld) endGimbalStick()
        programmedMove.onChange = { state ->
            if (state.failure != null) presentControlNote("Programmed move was not applied by the camera.")
        }
        if (!programmedMove.start(take, source, LunaMotionService.PROGRAM_TIMING))
            presentControlNote("Programmed move is unavailable for the current camera state.")
    }
    fun pauseProgrammedMove() { if (programSceneActive) programmedMove.pause() }
    fun resumeProgrammedMove() { if (programSceneActive) programmedMove.resume() }
    fun restartProgrammedMove() {
        val progress = programmedMove.state.value.progress
        if (!programSceneActive || !progress.running || !progress.paused) return
        cancelProgrammedMove()
        runProgrammedMove()
    }
    fun cancelProgrammedMove() = programmedMove.cancel()

    // Focus and Deep Track.
    /** Last feed tap (elapsed ms, x, y) for the Deep Track double tap. */
    private var lastFeedTap: Triple<Long, Double, Double>? = null
    /** The operator's latest Deep Track box, until the camera reports it (core `TrackingStartPolicy`). */
    private var trackingRequest: TrackingBox? = null
    private var trackingRequestAt = 0L

    /**
     * iOS `handleFeedTap`: a second tap on the same spot within 0.35 s (`GimbalStick.doubleTapWindow`)
     * Deep Tracks whatever is there; a tap inside a face box Deep Tracks that face; anything else focuses.
     */
    fun handleFeedTap(x: Float, y: Float) {
        val nx = x.coerceIn(0f, 1f).toDouble()
        val ny = y.coerceIn(0f, 1f).toDouble()
        if (can(CameraCapability.TRACKING)) {
            val now = SystemClock.elapsedRealtime()
            val last = lastFeedTap
            if (last != null && now - last.first <= DOUBLE_TAP_WINDOW_MS && hypot(nx - last.second, ny - last.third) <= 0.06) {
                lastFeedTap = null
                return startTracking(LunaShellMapping.doubleTapTrackBox(nx, ny))
            }
            lastFeedTap = Triple(now, nx, ny)
            val hud = _trackingHud.value
            FaceTrackTap.boxIfTapped(hud.overlay, nx, ny, hud.dimmedFaces)?.let { return startTracking(it) }
        }
        tapFocus(x, y)
    }

    /** iOS `applyNotification`: 8315 Deep Track state (the camera ends tracking) and 8201 capture stopped. */
    private fun applyNotice(notice: CameraNotice) {
        when (notice) {
            is CameraNotice.Tracking -> if (tracking.ingest(notice) && !tracking.snapshot.active) trackingRequest = null
            is CameraNotice.CaptureStopped -> {
                if (notice.errorCode != 0L) presentControlNote("Recording stopped by the camera (code ${notice.errorCode}).")
                _mediaCaptured.tryEmit(Unit)
            }
        }
    }

    /** Drop the camera's previous subject until it reports a box near the operator's new one. */
    private fun acceptsTrackFrame(frame: CameraTrackFrame): Boolean {
        val requested = trackingRequest ?: return true
        if (frame.state != CameraTrackState.TRACKING) return true
        val box = TrackingBox(frame.x, frame.y, frame.width, frame.height)
        val since = (SystemClock.elapsedRealtime() - trackingRequestAt) / 1000.0
        if (!TrackingStartPolicy.accepts(box, requested, since)) return false
        trackingRequest = null
        return true
    }
    fun tapFocus(x: Float, y: Float) {
        if (!supportsTapFocus) return
        // iOS `markFocus`: a tap focus ends Deep Track.
        cancelTracking()
        lastTapFocusAt = SystemClock.elapsedRealtime()
        faceBox = null
        refreshTrackingHud()
        _focusPoint.value = x to y
        // The backend centres its official ROI on the tap (iOS: 0.1545 x 0.2727).
        scope.launch { if (!tracking.focus(x.toDouble(), y.toDouble())) presentControlNote("Focus did not reach the camera.") }
    }
    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) =
        startTracking(TrackingBox((x - width / 2).toDouble(), (y - height / 2).toDouble(), width.toDouble(), height.toDouble()))
    fun startTracking(box: TrackingBox) {
        if (!can(CameraCapability.TRACKING)) return unavailable("Deep Track")
        if (box.isTooSmall) return presentControlNote("Frame Too Small")
        faceBox = null
        trackingRequest = box
        trackingRequestAt = SystemClock.elapsedRealtime()
        // Undispatched: the search box shows before this returns, as the request goes out.
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            if (!tracking.start(LunaShellMapping.lunaBox(box))) presentControlNote("Deep Track did not start.")
        }
    }
    fun cancelSubjectTracking() = cancelTracking()
    fun cancelTracking() {
        if (!tracking.snapshot.active) return
        trackingRequest = null
        scope.launch(start = CoroutineStart.UNDISPATCHED) { tracking.cancel() }
    }
    fun handleGamepadAction(action: GamepadOperatorAction) {
        when (action) {
            GamepadOperatorAction.RECORD -> if (!controlBusy.value) pressShutter()
            GamepadOperatorAction.RECENTER -> performGimbalDoubleTap()
            GamepadOperatorAction.FLIP -> flipGimbal()
            GamepadOperatorAction.TRACK -> handleGamepadTrackToggle()
            GamepadOperatorAction.ZOOM_CHIP_IN ->
                control.commitZoomCycle(CamFov.nextJump(control.state.value.pendingZoom ?: zoomCycleFrom(), zoomStops()))
            GamepadOperatorAction.ZOOM_CHIP_OUT ->
                control.commitZoomCycle(CamFov.previousJump(control.state.value.pendingZoom ?: zoomCycleFrom(), zoomStops()))
            GamepadOperatorAction.ISO_UP, GamepadOperatorAction.ISO_DOWN -> {
                val status = _status.value
                if (status.isoIndex < 0) return
                val steps = if (action == GamepadOperatorAction.ISO_UP) 1 else -1
                CameraCommands.isoStepped(status.isoIndex, steps, status.availableIsoIndices)?.let(::setIsoIndex)
            }
            GamepadOperatorAction.SHUTTER_OPEN, GamepadOperatorAction.SHUTTER_CLOSE -> {
                val status = _status.value
                val steps = if (action == GamepadOperatorAction.SHUTTER_OPEN) 1 else -1
                val next = CameraCommands.shutterSteppedDenom(status.shutterDenom, steps, status.availableShutterDenoms) ?: return
                if (GamepadShutterSync.shouldPersistPreferredAngle(
                        OperatorPrefs.shutterUsesAngle(appContext), status.isPhoto, status.expoMode == CameraCommands.EXPO_AUTO,
                    )
                ) OperatorPrefs.setShutterAngleDegrees(appContext, GamepadShutterSync.preferredAngle(next, status.fps))
                setShutterDenom(next)
            }
        }
    }
    fun handleGamepadTrackToggle() = if (isTrackingActive) cancelTracking() else startTracking(0.5f, 0.5f)
    /** iOS `resetFocusPoint`: `markFocus(0.5, 0.5)`, which also ends Deep Track. */
    fun resetFocusPoint() = tapFocus(0.5f, 0.5f)
    fun applyDetectedFaces(faces: List<TrackingBox>) {
        if (!_wantsFaceDetect.value) return clearFaceAF()
        val now = SystemClock.elapsedRealtime()
        val dt = lastFaceAt?.let { (now - it) / 1000.0 } ?: 0.04
        lastFaceAt = now
        val moving = motion.isHeld
        sceneFaces = faces.take(SceneFacePolicy.MAX_FACES)
        if (isTrackingActive || !FaceAFPolicy.wantsFaceAF(_status.value.focusMode, _faceAFArmed.value)) {
            faceBox = null
            lastFaceHitAt = null
            return refreshTrackingHud()
        }
        val sinceHit = FaceTrackHold.secondsSinceHit(lastFaceHitAt, now)
        val hit = sceneFaces.filter { FaceTrackHold.shouldAccept(detected = it, last = faceBox, secondsSinceHit = sinceHit, sceneMoving = moving) }.maxByOrNull { it.area }
        if (hit != null) {
            lastFaceHitAt = now
            faceBox = FaceTrackHold.follow(faceBox, hit, dt.coerceIn(1.0 / 120.0, 0.08), moving)
            refreshTrackingHud()
        } else {
            tickFaceHold(now)
        }
    }
    /** iOS `tickFaceBoxes`: drop the painted faces after the miss timeout. */
    private fun tickFaceHold(now: Long = SystemClock.elapsedRealtime()) {
        if (!FaceTrackHold.shouldDrop(FaceTrackHold.secondsSinceHit(lastFaceHitAt, now), motion.isHeld)) return
        if (faceBox == null && sceneFaces.isEmpty()) return
        faceBox = null
        sceneFaces = emptyList()
        lastFaceHitAt = null
        refreshTrackingHud()
    }
    fun wantsFaceFrame(): Boolean = faceDetector.wantsFrame()
    fun considerFaceFrame(frame: LiveFaceDetector.Frame) {
        if (!_wantsFaceDetect.value) { frame.release(); return clearFaceAF() }
        faceDetector.consider(frame) { hits -> applyDetectedFaces(hits) }
    }
    /** iOS `armFaceAFAfterFirstPicture`. */
    fun noteLiveFrame() {
        if (_faceAFArmed.value || faceAFArmJob != null) return
        faceAFArmJob = scope.launch {
            while (isActive && !_faceAFArmed.value) {
                delay(100)
                if (decoder.lastPresentedAt != null) { _faceAFArmed.value = true; publishFaceDetectWanted() }
            }
            faceAFArmJob = null
        }
    }
    /** iOS `wantsFaceDetect`: AF-C once the picture is up. ponytail: no face-priority exposure term; the Luna meters faces itself (METER tile). */
    private fun publishFaceDetectWanted() {
        val next = FaceAFPolicy.wantsFaceDetect(_status.value.focusMode, _faceAFArmed.value, facePriority = false, expoAuto = false)
        if (_wantsFaceDetect.value != next) _wantsFaceDetect.value = next
        if (!next) { faceTickJob?.cancel(); faceTickJob = null; if (faceBox != null || sceneFaces.isNotEmpty()) clearFaceAF(); return }
        if (faceTickJob == null) faceTickJob = scope.launch { while (isActive) { delay(50); tickFaceHold() } }
    }
    private fun clearFaceAF() {
        faceBox = null
        sceneFaces = emptyList()
        lastFaceAt = null
        lastFaceHitAt = null
        refreshTrackingHud()
    }

    // Native render/control demand reads the common gallery's actual app binding until I6.
    fun beginMediaBrowse() { isBrowsingMedia = true }
    fun endMediaBrowse() { isBrowsingMedia = false }

    // White balance: kelvin 2000...10000 or auto; the Luna has no tint.
    fun setWhiteBalanceAuto(tint: Int? = null) {
        if (canSendControl()) control.set(SettingValue.WhiteBalance(WhiteBalanceValue.Auto), "WB Auto")
    }
    fun setWhiteBalance(kelvin: Int, tint: Int) {
        if (!canSendControl()) return
        // fw 1.1.15 applies kelvin 3.5 to 3.9 s after the SET; the session waits for the readback.
        val clamped = kelvin.coerceIn(2_000, 10_000)
        control.set(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(clamped)), "WB ${clamped}K")
    }
    // AF-S, AF-C and Product Showcase (iOS `setFocusOption`); the shared drum sends AF-C then a track, so the last wins.
    fun setFocusMode(continuous: Boolean) = setFocusOption(if (continuous) FocusOption.CONTINUOUS_DEFAULT else FocusOption.SINGLE)
    fun setFocusTrack(mode: Int) { FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, mode)?.let(::setFocusOption) }
    private fun setFocusOption(option: FocusOption) {
        if (!canSendControl()) return
        val mode = LunaShellMapping.cameraFocusMode(option) ?: return presentControlNote("${option.chip} is not offered by this camera.")
        pins.focus = pin(option, SystemClock.elapsedRealtime(), 3_000)
        _status.value = LunaShellMapping.withFocus(_status.value, option)
        coalesce("focus") { sendControl("Focus ${option.chip}", onFail = { pins.focus = null }) { setFocusMode(mode) } }
    }
    fun refreshFocusTrack() = Unit

    /** fw 1.1.15 stores option 46 3.7 to 4.9 s after the SET. */
    fun setFaceMetering(on: Boolean) {
        if (!canSendControl()) return
        val previous = _faceMetering.value
        val pin = pin(on, SystemClock.elapsedRealtime(), 6_000)
        val source = nativeCaptureSource()
        pins.faceMetering = pin
        _faceMetering.value = on
        // A later choice, or a replaced session or camera, owns the value: this request's callbacks retire.
        val current = { pins.faceMetering === pin && nativeCaptureSource() == source }
        // The usual read 0.4 s after the SET is too early for 46; read again before the pin lapses.
        sendControl(if (on) "Metering Face" else "Metering Matrix", admission = current,
            onFail = { pins.faceMetering = null; _faceMetering.value = previous },
            onSuccess = { scope.launch { delay(5_200); if (current()) controls?.requestSettingsRefresh() } }) {
            setFaceMetering(on)
        }
    }

    fun setColorMode(mode: Int, hopEnabled: Boolean = false) {
        if (!canSendControl()) return
        val previous = _status.value.colorMode
        if (_status.value.isRecording && mode != previous) return presentControlNote(ControlHud.RECORDING_COLOR_LOCK_NOTE)
        if (mode !in LunaShellMapping.colorModes) return
        pins.color = pin(mode, SystemClock.elapsedRealtime(), 3_000)
        _status.value = _status.value.copy(colorMode = mode)
        sendControl(CameraCommands.colorLabel(mode, profile = profile.labels), onFail = { pins.color = null; _status.value = _status.value.copy(colorMode = previous) }) {
            setColorProfile(LunaShellMapping.colorProfile(mode))
        }
    }

    fun setNativeRecordingFormat(value: com.opencapture.opencine.insta360.shell.CameraRecordFormat): Boolean {
        if (!canSendControl() || lastReadout?.shootingMode == null || _status.value.isPhoto ||
            control.state.value.snapshot?.recording?.value != com.opencapture.opencine.core.RecordingState.IDLE || value !in _nativeFormats.value) return false
        val source = nativeCaptureSource() ?: return false
        val previous = _nativeFormat.value
        val pin = NativeCapturePin(source, pin(value, nativePinNow(), 3_000))
        nativeFormatPin = pin
        _nativeFormat.value = value
        val dimensions = com.opencapture.opencine.core.CameraRecordingFormat.Dimensions.measured(value.width, value.height)
        val format = com.opencapture.opencine.core.CameraRecordingFormat.measured(dimensions, com.opencapture.opencine.core.Rational.frameRate(value.fps))
        val label = com.opencapture.opencine.appkit.MonitorCapturePresentation.recordingLabel(format) ?: "Format"
        // Decided from the state before the write; sent only after the camera takes the format, so a
        // refused format keeps the angle.
        val rematch = previous?.let {
            CorePresentation.angleRematchDenom(control.state.value.snapshot, OperatorPrefs.shutterAngleDegrees(appContext),
                usesAngle = OperatorPrefs.shutterUsesAngle(appContext), isPhoto = _status.value.isPhoto,
                previousFps = it.fps.roundToInt(), nextFps = value.fps.roundToInt(),
                available = _status.value.availableShutterDenoms, currentDenom = _status.value.shutterDenom)
        }
        sendControl(label, admission = { nativeFormatPin === pin && pin.source == nativeCaptureSource() },
            onFail = { nativeFormatPin = null; _nativeFormat.value = previous },
            onSuccess = { rematch?.let(::setShutterDenom) }) { setRecordFormat(value.id) }
        return true
    }

    fun setNativeRecordingColor(value: com.opencapture.opencine.insta360.shell.CameraColorProfile): Boolean {
        if (!canSendControl() || lastReadout?.shootingMode == null ||
            control.state.value.snapshot?.recording?.value != com.opencapture.opencine.core.RecordingState.IDLE ||
            value !in com.opencapture.opencine.insta360.shell.nativeRecordingColorProfiles) return false
        val source = nativeCaptureSource() ?: return false
        val previous = _nativeColor.value
        val pin = NativeCapturePin(source, pin(value, nativePinNow(), 3_000))
        nativeColorPin = pin
        _nativeColor.value = value
        sendControl(value.label, admission = { nativeColorPin === pin && pin.source == nativeCaptureSource() },
            onFail = { nativeColorPin = null; _nativeColor.value = previous }) { setColorProfile(value) }
        return true
    }

    fun setVideoFormat(format: VideoFormat, fromOperator: Boolean = true): Boolean {
        if (!canSendControl()) return false
        val previous = _status.value
        if (previous.isPhoto) return false
        if (previous.isRecording) { presentControlNote(ControlHud.RECORDING_COLOR_LOCK_NOTE); return false }
        val raw = formatTable[format] ?: run { presentControlNote("${format.chipLabel} is not available in this mode."); return false }
        val formatPin = pin(format, SystemClock.elapsedRealtime(), 3_000)
        pins.format = formatPin
        _status.value = previous.copy(resolutionCode = format.resolution.rawValue, fpsIndex = format.frameRate.rawValue, fps = format.frameRate.fps)
        sendControl(format.chipLabel, onFail = {
            if (pins.format === formatPin) {
                pins.format = null
                _status.value = _status.value.copy(resolutionCode = previous.resolutionCode, fpsIndex = previous.fpsIndex, fps = previous.fps)
            }
        }) { setRecordFormat(raw) }
        // Angle mode is ours: Core decides when the chosen degrees owe a new 1/N (only an
        // established manual video exposure; never an unknown one).
        ShutterAngle.formatRematch(
            degrees = OperatorPrefs.shutterAngleDegrees(appContext),
            usesAngle = OperatorPrefs.shutterUsesAngle(appContext),
            manual = previous.expoMode == CameraCommands.EXPO_MANUAL,
            isPhoto = previous.isPhoto,
            previousFps = previous.fps,
            nextFps = format.frameRate.fps,
            available = previous.availableShutterDenoms,
        )?.denom?.takeIf { it != previous.shutterDenom }?.let(::setShutterDenom)
        return true
    }
    fun setResolutionFps(res: Int, fpsIndex: Int): Boolean = VideoFormat.parse(res, fpsIndex)?.let(::setVideoFormat) ?: false
    // The Luna exposes no audio controls or level meters.

    companion object {
        /** fw 1.1.15 official presets, same as iOS `LunaShellMapping.zoomChips`; the ceiling is appended when larger. */
        val LUNA_ZOOM_CHIPS = listOf(1.0, 2.0, 3.0, 6.0, 15.0)
        /** iOS `GimbalStick.doubleTapWindow` (0.35 s) for the feed double tap to Deep Track. */
        const val DOUBLE_TAP_WINDOW_MS = 350L
        /**
         * IA-366: any confirmed live picture clears a waiting recovery card unless the bounded
         * episode is itself retrying; then the episode publishes its own recovery.
         */
        internal fun retiresRecoveryOnLive(episodeRunning: Boolean): Boolean = !episodeRunning
    }
}
