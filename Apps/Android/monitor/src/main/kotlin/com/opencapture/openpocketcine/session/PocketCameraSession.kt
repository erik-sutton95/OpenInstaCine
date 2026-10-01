package com.opencapture.openpocketcine.session

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.CaptureLists
import com.opencapture.openpocketcine.CaptureShutterPolicy
import com.opencapture.openpocketcine.GamepadOperatorAction
import com.opencapture.openpocketcine.GamepadShutterSync
import com.opencapture.openpocketcine.EvComp
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.core.CameraSession as CameraSessionSeam
import com.opencapture.openpocketcine.core.CoreSessionSource
import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraCommandIntent
import com.opencapture.opencine.core.CameraSession as CoreCameraSession
import com.opencapture.opencine.core.CameraSnapshot as CoreSnapshot
import com.opencapture.opencine.core.CommandPreconditions
import com.opencapture.opencine.core.CommandReceipt
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.feed.FacePriorityExposure
import com.opencapture.opencine.media.SerialSessionGate
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.diagnostics.FeedDecoderErrorOrigin
import com.opencapture.openpocketcine.diagnostics.FeedIncidentAges
import com.opencapture.openpocketcine.diagnostics.FeedIncidentBreadcrumb
import com.opencapture.openpocketcine.diagnostics.FeedIncidentBreadcrumbKind
import com.opencapture.openpocketcine.diagnostics.FeedIncidentDecoder
import com.opencapture.openpocketcine.diagnostics.FeedIncidentLifecycle
import com.opencapture.openpocketcine.diagnostics.FeedIncidentQueue
import com.opencapture.openpocketcine.diagnostics.FeedIncidentRates
import com.opencapture.openpocketcine.diagnostics.FeedIncidentOrigin
import com.opencapture.openpocketcine.diagnostics.FeedIncidentRuntime
import com.opencapture.openpocketcine.diagnostics.ReliabilityReporting
import com.opencapture.openpocketcine.diagnostics.FeedIncidentSessionContext
import com.opencapture.openpocketcine.diagnostics.FeedIncidentSnapshot
import com.opencapture.openpocketcine.diagnostics.FeedRepairPhase
import com.opencapture.openpocketcine.diagnostics.FeedRepairRecord
import com.opencapture.openpocketcine.diagnostics.RecoveryAction
import com.opencapture.openpocketcine.diagnostics.RecoveryEffect
import com.opencapture.openpocketcine.diagnostics.RecoveryEffectLog
import com.opencapture.openpocketcine.diagnostics.RecoveryReason
import com.opencapture.openpocketcine.BuildConfig
import android.os.Build
import java.util.UUID
import com.opencapture.openpocketcine.pairing.CameraApJoiner
import com.opencapture.openpocketcine.pairing.CameraConnectionSetup
import com.opencapture.openpocketcine.multiview.MultiviewNetworkStore
import com.opencapture.openpocketcine.ShutterAngle
import com.opencapture.openpocketcine.core.CameraTrackFrame
import com.opencapture.openpocketcine.core.CameraTrackState
import com.opencapture.openpocketcine.pairing.CameraWifiCredentialStore
import com.opencapture.openpocketcine.pairing.CameraWifiResolution
import com.opencapture.openpocketcine.pairing.WifiLowLatencyLock
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
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
import com.opencapture.openpocketcine.MonitorConfiguration
import com.opencapture.openpocketcine.core.CameraBackend
import com.opencapture.openpocketcine.core.CameraCapability
import com.opencapture.openpocketcine.core.CameraNotice
import com.opencapture.openpocketcine.core.CameraControls
import com.opencapture.openpocketcine.core.CameraGimbalAngle
import com.opencapture.openpocketcine.core.CameraIdentity
import com.opencapture.openpocketcine.core.CameraMediaStore
import com.opencapture.openpocketcine.core.CameraReadout
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import com.opencapture.opencine.media.LivePipelineCadence

/** Main-thread admission closes before negotiation is dispatched to the IO worker. */
internal class EndpointCommandAdmission {
    private var owner: Any? = null

    fun begin(): Any = Any().also { owner = it }

    fun finish(token: Any) {
        if (owner === token) owner = null
    }

    fun allows(isClosed: Boolean, isRebuilding: Boolean): Boolean =
        owner == null && !isClosed && !isRebuilding
}

/** Keep blocking negotiation and its post-handshake enable owned by the same live link. */
internal suspend fun <T : Any> repairDatalinkEndpoint(
    link: T,
    isCurrent: (T) -> Boolean,
    reopen: (T) -> Unit,
    pictureTimeoutMs: Long = LiveViewEnablePolicy.ENDPOINT_PICTURE_GRACE_MS,
    waitForPicture: suspend () -> Unit = {},
    recoverSession: () -> Unit = {},
    commandAdmission: EndpointCommandAdmission = EndpointCommandAdmission(),
    prepare: () -> Unit = {},
    ownsPicture: () -> Boolean = { true },
    enable: () -> Unit,
) {
    val commandOwner = commandAdmission.begin()
    var negotiated = false
    try {
        prepare()
        interruptibleDatalinkOpen { reopen(link) }
        negotiated = true
        coroutineContext.ensureActive()
        if (!isCurrent(link)) return
        commandAdmission.finish(commandOwner)
        if (!ownsPicture()) return
        enable()
        val presented = kotlinx.coroutines.withTimeoutOrNull(pictureTimeoutMs) {
            waitForPicture()
            true
        } ?: false
        coroutineContext.ensureActive()
        if (!presented && isCurrent(link) && ownsPicture()) recoverSession()
    } catch (error: kotlinx.coroutines.CancellationException) {
        throw error
    } catch (_: Exception) {
        coroutineContext.ensureActive()
        if (isCurrent(link) && (!negotiated || ownsPicture())) recoverSession()
    } finally {
        commandAdmission.finish(commandOwner)
    }
}

internal fun acceptsGimbalConfiguration(
    hasGimbal: Boolean, live: Boolean, sceneActive: Boolean, warming: Boolean,
    recovering: Boolean, videoStale: Boolean, hasDatalink: Boolean,
): Boolean = hasGimbal && live && sceneActive && !warming && !recovering && !videoStale && hasDatalink

/** A serialized command chain keeps its original endpoint epoch across every suspension. */
internal class EndpointCommandEpoch(val generation: Long) :
    kotlin.coroutines.AbstractCoroutineContextElement(Key) {
    companion object Key : kotlin.coroutines.CoroutineContext.Key<EndpointCommandEpoch>
}

internal suspend fun ensureEndpointCommandCurrent(currentGeneration: Long) {
    coroutineContext.ensureActive()
    val epoch = coroutineContext[EndpointCommandEpoch]
    if (epoch != null && epoch.generation != currentGeneration) {
        throw kotlinx.coroutines.CancellationException("camera command endpoint changed")
    }
}


/**
 * OpenInstaCine session. Same view-facing surface as OpenPocketCine's DUML session, so every
 * shared screen binds unchanged; the Osmo spine is replaced by the injected [CameraBackend]
 * (Luna: BLE consent, camera Wi-Fi, UCD2 on TCP 6666). Controls exist only where the backend
 * advertises the capability and implements [CameraControls]; everything else is a no-op that
 * leaves the shared sheets on their unavailable state. Historical class name kept for JNI and
 * source compatibility with the upstream shell.
 */
class PocketCameraSession(
    context: Context, borrowing: HevcDecoder? = null,
    // Multiview is off on Luna ([supportsMultiview]); the lease is accepted for the shared AppModel only.
    @Suppress("UNUSED_PARAMETER") controlLease: MultiviewControlLease? = null,
) : CameraSessionSeam {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val backend: CameraBackend = MonitorConfiguration.createBackend(appContext)
    private val controls: CameraControls? = backend as? CameraControls
    /** This session's names and media host (STATE-01: per session, never a launch-time global). */
    val profile: CameraProfile = LunaShellMapping.profile
    /** This source's learned picture EV calibration (STATE-01: one meter per session, keyed by source). */
    internal val pictureEV by lazy { com.opencapture.openpocketcine.PictureEVMeter.stored(appContext) }
    val capabilities: Set<CameraCapability> get() = backend.capabilities
    private fun can(capability: CameraCapability) = controls != null && capability in capabilities

    /** Multiview drives several DUML datalinks; the Luna shell has one camera link. */
    val supportsMultiview: Boolean get() = false
    internal val cadence = LivePipelineCadence()
    @Volatile internal var debugVideoPacketAdmission: (() -> Boolean)? = null
    internal var debugCameraSetResult: ((Int, Boolean) -> Unit)? = null
    internal val pendingCameraSetCount: Int get() = 0
    val isMultiviewBorrowed = borrowing != null
    val decoder = borrowing ?: HevcDecoder(cadence)

    override val phase: ConnectionPhase get() = backend.phase.value
    val phaseFlow: StateFlow<ConnectionPhase> get() = backend.phase
    val failure: StateFlow<String?> get() = backend.failure
    val found: StateFlow<List<FoundCamera>> =
        backend.found.map { cameras -> cameras.map(::displayCamera) }.stateIn(scope, SharingStarted.Eagerly, emptyList())
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

    private val _controlBusy = MutableStateFlow(false)
    val controlBusy: StateFlow<Boolean> = _controlBusy.asStateFlow()
    /** Camera media over the control link, when the backend offers it (Luna: UCD2 list + HTTP). */
    val media: CameraMediaStore? get() = (backend as? CameraMediaStore)?.takeIf { CameraCapability.CAMERA_MEDIA in capabilities }
    private val pins = LunaControlPins()
    // OpenCineCore (CORE-02): ISO, shutter, white balance and record go only through [core].
    private var core: CoreCameraSession? = null
    private var coreFeed: Job? = null
    private var coreSnapshot: CoreSnapshot? = null
    private val pendingSettings = mutableMapOf<SettingKey, PendingSetting>()
    private var recordOperation: OperationID? = null
    private var formatTable: Map<VideoFormat, Long> = emptyMap()
    private var lastReadout = CameraReadout()
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

    // Programmed moves: waypoints from GET_ANGLE, the path streamed as SET_ANGLE (iOS 309049f).
    private val _gimbalMoveCountdown = MutableStateFlow<Int?>(null)
    val gimbalMoveCountdown: StateFlow<Int?> = _gimbalMoveCountdown.asStateFlow()
    val gimbalMoveReadout: StateFlow<String> = MutableStateFlow("").asStateFlow()
    var gimbalRamp: GimbalRamp = GimbalRamp.OFF
    var gimbalDoubleTap: GimbalDoubleTap = GimbalDoubleTap.RECENTER
    private val _gimbalMode = MutableStateFlow(GimbalMode.FOLLOW)
    val gimbalMode: StateFlow<GimbalMode> = _gimbalMode.asStateFlow()
    private val _gimbalSpeed = MutableStateFlow(GimbalSpeed.DEFAULT)
    val gimbalSpeed: StateFlow<GimbalSpeed> = _gimbalSpeed.asStateFlow()
    private val _gimbalProgram = MutableStateFlow(GimbalProgram())
    val gimbalProgram: StateFlow<GimbalProgram> = _gimbalProgram.asStateFlow()
    private val _gimbalMovePaused = MutableStateFlow(false)
    val gimbalMovePaused: StateFlow<Boolean> = _gimbalMovePaused.asStateFlow()
    private val _gimbalMoveRunning = MutableStateFlow(false)
    val gimbalMoveRunning: StateFlow<Boolean> = _gimbalMoveRunning.asStateFlow()
    val hasGimbal: Boolean get() = connectedCamera != null && can(CameraCapability.GIMBAL)
    val supportsZoom: Boolean get() = connectedCamera != null && can(CameraCapability.ZOOM)
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
    /** Luna joins only its own access point: the shared Wi-Fi and Hotspot setups (#406) are DJI station mode. */
    val connectionSetup: CameraConnectionSetup get() = CameraConnectionSetup.CAMERA_WIFI
    val setupProgress: StateFlow<String?> = MutableStateFlow<String?>(null).asStateFlow()
    fun useSetup(setup: CameraConnectionSetup, network: MultiviewNetworkStore.Network?, restoreAccessPoint: Boolean) = Unit
    /** iOS `supportsFocusMode`: AF-S, AF-C and Product Showcase (option 93). */
    val supportsFocusMode: Boolean get() = can(CameraCapability.CAMERA_SETTINGS)
    val supportsTapFocus: Boolean get() = can(CameraCapability.FOCUS)
    /** iOS `supportsAudio`: the Luna sends no audio levels, so AUDIO is hidden live (clip playback keeps its meters). */
    val supportsAudio: Boolean get() = can(CameraCapability.AUDIO)
    /** iOS `reportsMeteredEV`: the Luna sends none, so the EV meter reads the picture. */
    val reportsMeteredEV: Boolean get() = CameraCapability.METERED_EV in capabilities
    /** DJI camcap hop to the log curve's native ISO on a color change; the Luna has none, so the ISO sheet hides the toggle. */
    val supportsNativeIsoHop: Boolean get() = CameraCapability.NATIVE_ISO_HOP in capabilities
    /** iOS `faceMetering`: true Face Priority, false Matrix, null until the camera reports it (METER tile hidden). */
    private val _faceMetering = MutableStateFlow<Boolean?>(null)
    val faceMetering: StateFlow<Boolean?> = _faceMetering.asStateFlow()

    /** The calibration context of the picture EV estimate: device, recording profile and curve, metering. */
    internal fun pictureEVSource(transfer: com.opencapture.openpocketcine.feed.MonitorTransfer) =
        com.opencapture.openpocketcine.PictureEVMeter.Source(
            device = coreSnapshot?.device?.value ?: connectedCamera?.id ?: "unknown",
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
    private val _connectionTargetId = MutableStateFlow<String?>(null)
    val connectionTargetId: StateFlow<String?> = _connectionTargetId.asStateFlow()
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
    private var trackBoxes = LunaTrackBoxes()
    private fun showTrack(next: LunaTrackBoxes) { trackBoxes = next; refreshTrackingHud() }
    /** Deep Track boxes plus the AF-C face box and the dimmed scene faces (upstream `refreshTrackingHud`). */
    private fun refreshTrackingHud() {
        val track = trackBoxes
        val sinceTap = lastTapFocusAt?.let { (SystemClock.elapsedRealtime() - it) / 1000.0 }
        val overlay = if (FaceAFPolicy.shouldHoldTapBox(sinceTap)) track.hud.overlay.takeUnless { it is FocusOverlay.Face } ?: FocusOverlay.Focus
            else FaceAFPolicy.resolve(_status.value.focusMode, track.locked, track.search, track.subject, faceBox)
        val hiding = (overlay as? FocusOverlay.Face)?.box
        val occluder = when (overlay) {
            is FocusOverlay.Subject -> overlay.box
            is FocusOverlay.Search -> overlay.box
            else -> track.subject
        }
        _trackingHud.value = TrackingHud(overlay, sceneFaces, SceneFacePolicy.dimmed(sceneFaces, hiding, occluder), isTracking = track.active)
    }
    private val _trackingHud = MutableStateFlow(TrackingHud())
    val trackingHud: StateFlow<TrackingHud> = _trackingHud.asStateFlow()
    val isReconnecting: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
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

    init {
        scope.launch {
            backend.snapshot.collect { value ->
                value.batteryPercent?.let { _status.value = _status.value.copy(batteryPercent = it) }
            }
        }
        controls?.let { link ->
            scope.launch { link.readout.collect(::applyReadout) }
            scope.launch { link.trackFrames.collect { frame -> if (acceptsTrackFrame(frame)) trackBoxes.apply(frame)?.let(::showTrack) } }
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
                when (value) {
                    ConnectionPhase.LIVE -> {
                        holdsMonitor = true; _recoveryState.value = SessionRecoveryUi.Idle; resetFrameClock()
                        startGimbalAnglePoll()
                    }
                    ConnectionPhase.FAILED -> {
                        resetFrameClock(); stopGimbalAngle()
                        if (holdsMonitor) beginSessionRecovery()
                    }
                    ConnectionPhase.IDLE -> {
                        resetFrameClock(); stopGimbalAngle()
                        faceAFArmJob?.cancel(); faceAFArmJob = null; _faceAFArmed.value = false; publishFaceDetectWanted()
                        recoveryJob?.cancel(); recoveryJob = null
                        holdsMonitor = false; _recoveryState.value = SessionRecoveryUi.Idle
                        pins.clear(); recordStartedAt = null; _controlBusy.value = false
                    }
                    else -> Unit
                }
            }
        }
        if (borrowing == null) {
            scope.launch(Dispatchers.Default) {
                backend.frames.collect { frame ->
                    noteFrameClock(frame.timestampMicros)
                    videoPackets += 1
                    accessUnits += 1
                    if (decoder.decode(frame.annexB)) { framesEnqueued += 1; hasVideoFormat = true }
                }
            }
        }
    }

    private fun displayCamera(value: CameraIdentity) = FoundCamera(
        value.id, value.id, value.advertisedName,
        CameraModel(
            name = value.modelName, datalinkPort = 0, tcpPoke = false, verified = true, pairingToken = "luna",
            family = "generic", supportsTapFocus = CameraCapability.FOCUS in capabilities, supportsFocusMode = supportsFocusMode,
            usesCapturedLiveEnable = false, zoomStops = lunaZoomStops(), hasGimbal = CameraCapability.GIMBAL in capabilities,
            supportsZoom = CameraCapability.ZOOM in capabilities, sendsLiveViewPrepare = false, supportsAperture = false,
        ),
        null,
    )

    private fun lunaZoomStops(): List<Double> {
        val ceiling = controls?.zoomRange?.endInclusive ?: 1.0
        val stops = LUNA_ZOOM_CHIPS.filter { it <= ceiling }.toMutableList()
        if (stops.isEmpty()) stops += 1.0
        if (ceiling > stops.last() + 0.5) stops += ceiling
        return stops
    }

    // Connection.
    override fun startScan() = backend.startScan()
    fun startScan(reconnect: String?) { if (reconnect == null) startScan() else reconnect(reconnect) }
    fun reconnect(id: String) { _connectionTargetId.value = id; openCore(); backend.connect(id) }
    fun connect(camera: FoundCamera) {
        decoder.reset(); videoPackets = 0; hasVideoFormat = false
        _connectionTargetId.value = camera.id
        openCore()
        backend.connect(camera.id)
    }

    /** A fresh Core session per connection; recovery keeps it (its epoch advances on LIVE). */
    private fun openCore() {
        closeCore()
        val session = (backend as? CoreSessionSource)?.openSession() ?: return
        core = session
        coreFeed = scope.launch { session.snapshots.collect(::applyCoreSnapshot) }
    }

    /** Closing never sends a camera command; in particular it never stops a recording. */
    private fun closeCore() {
        coreFeed?.cancel(); coreFeed = null
        core?.let { session -> scope.launch { session.close(SessionCloseReason.REQUESTED) } }
        core = null; coreSnapshot = null; pendingSettings.clear()
        if (recordOperation != null) { recordOperation = null; _controlBusy.value = false }
    }

    private fun applyCoreSnapshot(snapshot: CoreSnapshot) {
        coreSnapshot = snapshot
        _status.update { CorePresentation.apply(snapshot, pendingSettings, it) }
    }

    private suspend fun finished(session: CoreCameraSession, command: CameraCommand): CommandReceipt {
        val receipt = session.submit(command)
        if (receipt.isFinished) return receipt
        return session.outcome(command.operation) ?: receipt
    }
    fun attachSurface(surface: Surface?) = decoder.attachSurface(surface)
    // Multiview needs a second DUML datalink; the Luna shell never offers it.
    fun updateMultiview(camera: FoundCamera?, driver: DatalinkDriver?, status: CameraStatus) = Unit
    val multiviewPose: GimbalStickMapping get() = GimbalStickMapping()
    fun adoptMultiviewPose(pose: GimbalStickMapping) = Unit
    fun receiveMultiview(frame: DumlFrame) = Unit
    fun releaseMultiview() = Unit
    override fun disconnect() {
        closeCore()
        backend.disconnect(); decoder.reset()
        holdsMonitor = false; hasVideoFormat = false
        _connectionTargetId.value = null
        showTrack(LunaTrackBoxes())
    }
    fun close() { closeCore(); backend.close(); decoder.reset(); scope.cancel() }
    fun noteSceneBecameInactive() = backend.sceneActive(false)
    fun noteSceneBecameActive() = backend.sceneActive(true)
    internal fun hasRecoveryPicture(startedAt: Long): Boolean = hasVideoFormat
    /** iOS `retrySessionRecovery`: the operator starts a fresh bounded run. */
    fun retrySessionRecovery() {
        dropGuard.reset()
        recoveryJob?.cancel(); recoveryJob = null
        _recoveryState.value = SessionRecoveryUi.Idle
        beginSessionRecovery()
    }
    private val dropGuard = SessionDropStormGuard()
    private var recoveryJob: Job? = null
    /**
     * iOS `beginSessionRecovery` + `runSessionRecoveryAttempts`: a live drop keeps the monitor on the last
     * frame and reconnects through the backend's BLE-first path, retrying at once then 0.5 s to 8 s
     * jittered, at most 8 attempts within 180 s; then the Recovery card waits for the operator.
     */
    private fun beginSessionRecovery() {
        if (recoveryJob?.isActive == true) return
        val state = _recoveryState.value
        if (state is SessionRecoveryUi.WaitingForOperator || state is SessionRecoveryUi.PausedAfterDrops) return
        val id = backend.connected.value?.id ?: return
        if (dropGuard.noteDrop(SystemClock.elapsedRealtime())) {
            _recoveryState.value = SessionRecoveryUi.PausedAfterDrops(dropGuard.dropsInWindow)
            return
        }
        Log.i("OpenInstaCine", "session: drop, bounded recovery")
        recoveryJob = scope.launch {
            val policy = SessionRecoveryPolicy.monitor
            var failures = 0
            val ended = kotlinx.coroutines.withTimeoutOrNull(SessionRecoveryPolicy.AUTOMATIC_RECOVERY_BUDGET_MS) {
                while (true) {
                    val next = policy.state(failures)
                    _recoveryState.value = next
                    if (next !is SessionRecoveryUi.Retrying) break
                    backend.connect(id)
                    kotlinx.coroutines.withTimeoutOrNull(2_000) { backend.phase.first { it != ConnectionPhase.FAILED } }
                    val outcome = backend.phase.first { it == ConnectionPhase.LIVE || it == ConnectionPhase.FAILED || it == ConnectionPhase.IDLE }
                    if (outcome != ConnectionPhase.FAILED) { Log.i("OpenInstaCine", "session: recovered after $failures failed attempt(s)"); break }
                    failures += 1
                    val decision = policy.decision(failures, Math.random())
                    if (decision !is SessionRecoveryDecision.Retry) { _recoveryState.value = policy.state(failures); break }
                    delay(decision.afterMs)
                }
            }
            // Budget spent: the attempt in flight may still land (LIVE clears the card); otherwise the operator decides.
            if (ended == null) _recoveryState.value = SessionRecoveryUi.WaitingForOperator(failures + 1)
        }
    }
    fun abandonRecoveryToMenu() = disconnect()

    // Status mapping (Luna readout to the shared CameraStatus), iOS `applyDeviceStatus`/`applySettings`/`applyCapture`.
    private fun applyReadout(readout: CameraReadout) {
        lastReadout = readout
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
        // ISO, shutter, WB and recording itself come from the Core session; the readout keeps the REC timer.
        coreSnapshot?.let { next = CorePresentation.apply(it, pendingSettings, next) }
        val recording = readout.recording == true
        if (recording && recordStartedAt == null) recordStartedAt = now - readout.captureSeconds * 1_000L
        if (!recording) recordStartedAt = null
        val elapsed = if (recording) maxOf(readout.captureSeconds, recordStartedAt?.let { ((now - it) / 1_000).toInt() } ?: 0) else 0
        next = next.copy(recordElapsedSec = elapsed)
        // The frame clock owns the timecode (set from the decode thread).
        _status.update { next.copy(timecode = it.timecode) }
        if (recordOperation == null && _controlBusy.value && !pins.photoInFlight) _controlBusy.value = false
        publishFaceDetectWanted()
    }

    // Timecode, iOS `noteFrameClock`. Frame stamps run on a camera clock that does not follow its
    // time of day, so each is pinned to the phone clock by the earliest arrival; with the camera
    // clock synced at live start (the backend), that is the camera's time-of-day timecode.
    @Volatile private var frameClockOffsetMs: Long? = null
    @Volatile private var lastTimecodeSecond: Long? = null

    private fun resetFrameClock() {
        frameClockOffsetMs = null; lastTimecodeSecond = null
        _status.update { it.copy(timecode = null) }
    }

    /** [stampMicros]: the frame's camera clock (Luna: its u64 ms header stamp, in microseconds). */
    private fun noteFrameClock(stampMicros: Long) {
        val stamp = stampMicros / 1_000
        val seen = System.currentTimeMillis() - stamp - FRAME_LATENCY_MS
        val offset = minOf(frameClockOffsetMs ?: seen, seen)
        frameClockOffsetMs = offset
        val wall = stamp + offset
        val second = Math.floorDiv(wall, 1_000L)
        // The HUD shows HH:MM:SS: publish once per displayed second.
        if (second == lastTimecodeSecond) return
        lastTimecodeSecond = second
        val zone = java.util.TimeZone.getDefault().getOffset(wall) / 1_000
        _status.update { it.copy(timecode = LunaShellMapping.timecode(wall / 1_000.0, zone, it.fps)) }
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
        request: suspend CameraControls.() -> Boolean,
    ) {
        val link = controls ?: return
        scope.launch {
            if (link.request()) {
                onSuccess()
                if (refresh) link.requestSettingsRefresh()
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

    // Record and photo. Record never lies: the lamp holds controlBusy until the Core session reports
    // the outcome. Start or stop is resolved from the session's current snapshot; unknown sends nothing.
    fun pressRecord() {
        if (!canSendControl() || recordOperation != null) return
        val session = core ?: return presentControlNote("Connect the camera to use its controls.")
        val snapshot = session.snapshots.value
        val intent = CorePresentation.recordIntent(snapshot.recording.value)
            ?: return presentControlNote("Recording state is not known yet. Try again in a moment.")
        val command = CameraCommand(intent, CommandPreconditions(snapshot))
        recordOperation = command.operation
        _controlBusy.value = true
        scope.launch {
            val receipt = finished(session, command)
            if (recordOperation != command.operation) return@launch
            recordOperation = null
            _controlBusy.value = false
            val stop = intent == CameraCommandIntent.StopRecording
            CorePresentation.note(receipt.stage, if (stop) "Stop" else "Record")?.let(::presentControlNote)
            if (stop && receipt.stage == CommandStage.Confirmed) _mediaCaptured.tryEmit(Unit)
        }
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
            CameraCommands.shootingModeLabel(raw, profile = profile).orEmpty(), refresh = false,
            onFail = { pins.shootingMode = null; _status.value = _status.value.copy(shootingMode = previous.shootingMode) },
        ) { setShootingMode(mode) }
    }

    // Exposure: ISO and shutter go to the Core session, which owns Luna's one exposure message.
    fun setIsoIndex(index: Int) {
        if (!canSendControl()) return
        val iso = if (index == 0) ISOValue.Auto else ISOValue.Manual(CameraCommands.isoValue(index) ?: return)
        submitSetting(SettingValue.Iso(iso), "ISO ${CameraCommands.isoLabel(index)}")
    }

    fun setShutterDenom(denom: Int) {
        if (!canSendControl() || denom <= 0) return
        submitSetting(SettingValue.Shutter(ShutterValue.Duration(Rational(1, denom))), "1/$denom")
    }

    /** Shows [value] at once; submits it after the coalescing window (latest per setting wins). */
    private fun submitSetting(value: SettingValue, label: String) {
        pendingSettings[value.key] = PendingSetting(OperationID(), value)
        coreSnapshot?.let { snapshot -> _status.update { CorePresentation.apply(snapshot, pendingSettings, it) } }
        coalesce(value.key.name) { submitPending(value.key, label) }
    }

    private fun submitPending(key: SettingKey, label: String) {
        val pending = pendingSettings[key] ?: return
        val session = core
        val snapshot = coreSnapshot
        if (session == null || snapshot == null) return finishSetting(key, pending.operation, "Connect the camera to use its controls.")
        val command = CameraCommand(CameraCommandIntent.Set(pending.value), CommandPreconditions(snapshot), pending.operation)
        scope.launch { finishSetting(key, pending.operation, CorePresentation.note(finished(session, command).stage, label)) }
    }

    private fun finishSetting(key: SettingKey, operation: OperationID, note: String?) {
        // A newer edit of the same setting owns the drum now.
        if (pendingSettings[key]?.operation != operation) return
        pendingSettings.remove(key)
        note?.let(::presentControlNote)
        applyReadout(lastReadout)
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
            submitSetting(SettingValue.Iso(ISOValue.Auto), "Auto exposure")
            return submitSetting(SettingValue.Shutter(ShutterValue.Auto), "Auto exposure")
        }
        // Manual needs a shutter: keep the current one, else the nearest offered 180 degrees.
        val status = _status.value
        val wanted = status.shutterDenom.takeIf { it > 0 } ?: (maxOf(status.fps, 25) * 2)
        val denom = status.availableShutterDenoms.minByOrNull { abs(it - wanted) } ?: wanted
        submitSetting(SettingValue.Shutter(ShutterValue.Duration(Rational(1, denom))), "Manual exposure")
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
    fun setApertureStrategy(raw: Int) = Unit
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
    private var stickJob: Job? = null
    @Volatile private var stick = 0.0 to 0.0
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
            if (aimJob?.isActive != true && stickJob?.isActive != true && !_gimbalMoveRunning.value && abs(pitch) > 0.3) {
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
        val link = controls?.takeIf { can(CameraCapability.GIMBAL) } ?: return
        anglePollJob?.cancel()
        anglePollJob = scope.launch {
            while (isActive) {
                link.gimbalAngle()?.let { gimbalAngle = it to SystemClock.elapsedRealtime() }
                delay(100)
            }
        }
    }
    private fun stopGimbalAngle() {
        cancelProgrammedMove(); aimJob?.cancel()
        anglePollJob?.cancel(); anglePollJob = null; gimbalAngle = null
    }
    private fun sendGimbalAngle(target: GimbalWaypoint) {
        val (pitch, yaw) = LunaGimbalAim.setAngle(target)
        scope.launch { controls?.gimbalSetAngle(pitch, yaw) }
    }
    /** iOS `aimGimbal`: one SET_ANGLE; the aim ends once GET_ANGLE reads within 0.5 deg, or after 8 s. */
    private fun aimGimbal(target: GimbalWaypoint) {
        if (!canSetGimbalConfiguration() || stickJob?.isActive == true || _gimbalMoveRunning.value) return
        aimJob?.cancel()
        aimJob = scope.launch {
            sendGimbalAngle(target)
            val started = SystemClock.elapsedRealtime()
            while (isActive && canSetGimbalConfiguration() && stickJob?.isActive != true) {
                val elapsed = SystemClock.elapsedRealtime() - started
                if (elapsed > 8_000) break
                val reading = gimbalAngle
                if (elapsed > 300 && reading != null && reading.second > started + 200 &&
                    LunaGimbalAim.reached(reading.first, target)
                ) break
                delay(33)
            }
        }
    }
    fun recenterGimbal() {
        if (!hasGimbal) return
        aimJob?.cancel()
        scope.launch { if (controls?.gimbalRecenter() != true) presentControlNote("Recenter did not reach the camera.") }
    }
    fun flipGimbal() {
        if (!hasGimbal) return
        scope.launch { if (controls?.gimbalFlip() != true) presentControlNote("Flip did not reach the camera.") }
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
            if (_gimbalMoveRunning.value) cancelProgrammedMove()
        }
        // Same shaping as the iOS Luna session: deadzone, ease-in curve, sensitivity scale.
        val dead = if (linear) CameraCommands.GIMBAL_STICK_DEADZONE else mapping.deadzone
        val still = hypot(x.toDouble(), y.toDouble()) < dead
        val scale = minOf(1.0, sensitivity.toDouble() / CameraCommands.GIMBAL_STICK_DEFAULT_SENSITIVITY)
        fun shaped(v: Double) = (if (linear) v else v * abs(v)) * scale
        val pan = if (still) 0.0 else if (assistMirror) -x.toDouble() else x.toDouble()
        val tilt = if (still) 0.0 else y.toDouble()
        stick = shaped(pan) to shaped(tilt)
        if (stickJob?.isActive == true) return
        // ponytail: fixed 20 Hz rate stream, same cadence as the iOS LunaStickStream.
        stickJob = scope.launch {
            while (isActive) {
                val (p, t) = stick
                controls?.gimbalStick(p, t)
                delay(50)
            }
        }
    }
    fun endGimbalStick() {
        stickJob?.cancel(); stickJob = null
        stick = 0.0 to 0.0
        if (hasGimbal) scope.launch { controls?.gimbalStick(0.0, 0.0) }
    }
    private fun canSetGimbalConfiguration() = hasGimbal && phase == ConnectionPhase.LIVE && !isBrowsingMedia
    fun setGimbalMode(mode: GimbalMode) {
        if (!canSetGimbalConfiguration()) return
        val previous = _gimbalMode.value
        pins.gimbalMode = pin(mode, SystemClock.elapsedRealtime(), 3_000)
        _gimbalMode.value = mode
        sendControl("Gimbal ${mode.label(profile)}", onFail = { pins.gimbalMode = null; _gimbalMode.value = previous }) {
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
        if (_gimbalMoveRunning.value || stickJob?.isActive == true) return presentControlNote(GimbalHudCopy.HOLD_STILL)
        val angle = freshGimbalAngle(300) ?: return presentControlNote(GimbalHudCopy.POSE_NOT_READY)
        _gimbalProgram.update { it.withPoint(slot, LunaGimbalAim.waypoint(angle, _zoomReadout.value)) }
    }
    fun clearGimbalWaypoint(slot: GimbalWaypointSlot) {
        cancelProgrammedMove()
        _gimbalProgram.update { it.withPoint(slot, null) }
    }
    fun setGimbalLegDuration(ab: Double? = null, bc: Double? = null) {
        if (_gimbalMoveRunning.value) cancelProgrammedMove()
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

    private var moveJob: Job? = null
    private var moveCanPause = false
    /** iOS `runProgrammedMove`: countdown while the head goes to A, then stream the path every 33 ms; loop ping-pongs. */
    fun runProgrammedMove() {
        if (!hasGimbal) return
        if (_gimbalMoveRunning.value) return cancelProgrammedMove()
        programmedZoomUnavailableReason()?.let { return presentControlNote(it) }
        val take = _gimbalProgram.value
        val a = take.a
        if (!canRunProgrammedMove || a == null || gimbalAngle == null) {
            return presentControlNote(if (take.canRun) GimbalHudCopy.POSE_NOT_READY else GimbalHudCopy.NEED_AB)
        }
        _controlNote.value = null
        aimJob?.cancel()
        if (stickJob?.isActive == true) endGimbalStick()
        _gimbalMoveRunning.value = true
        _gimbalMovePaused.value = false
        moveCanPause = false
        moveJob?.cancel()
        moveJob = scope.launch {
            sendGimbalAngle(a)
            for (remaining in 3 downTo 1) { _gimbalMoveCountdown.value = remaining; delay(1_000) }
            _gimbalMoveCountdown.value = null
            moveCanPause = true
            val duration = LunaGimbalAim.programDuration(take)
            Log.i("OpenInstaCine", "gimbal-move: start ${take.summary} duration=$duration")
            var clock = 0.0
            var last = SystemClock.elapsedRealtime()
            var reverse = false
            while (isActive) {
                if (phase != ConnectionPhase.LIVE) return@launch cancelProgrammedMove()
                val now = SystemClock.elapsedRealtime()
                if (!_gimbalMovePaused.value) clock += (now - last) / 1_000.0
                last = now
                if (clock >= duration) {
                    if (!take.loop) break
                    clock -= duration
                    reverse = !reverse
                }
                if (!_gimbalMovePaused.value) {
                    LunaGimbalAim.programPose(take, if (reverse) duration - clock else clock)?.let(::sendGimbalAngle)
                }
                delay(33)
            }
            LunaGimbalAim.programPose(take, if (reverse) 0.0 else duration)?.let(::sendGimbalAngle)
            Log.i("OpenInstaCine", "gimbal-move: done")
            finishProgrammedMove()
        }
    }
    // The head settles on the last target; re-sending the GET pose (about 70 ms stale) steps it back.
    fun pauseProgrammedMove() { if (_gimbalMoveRunning.value && moveCanPause) _gimbalMovePaused.value = true }
    fun resumeProgrammedMove() { if (_gimbalMoveRunning.value && moveCanPause) _gimbalMovePaused.value = false }
    fun restartProgrammedMove() {
        if (!_gimbalMoveRunning.value || !_gimbalMovePaused.value) return
        cancelProgrammedMove()
        runProgrammedMove()
    }
    fun cancelProgrammedMove() {
        moveJob?.cancel()
        finishProgrammedMove()
    }
    private fun finishProgrammedMove() {
        moveJob = null
        _gimbalMoveCountdown.value = null
        _gimbalMoveRunning.value = false
        _gimbalMovePaused.value = false
        moveCanPause = false
    }

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
            is CameraNotice.Tracking -> trackBoxes.notice(notice.active)?.let { next ->
                if (!next.active) trackingRequest = null
                showTrack(next)
            }
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
        scope.launch { if (controls?.tapFocus(x.toDouble(), y.toDouble()) != true) presentControlNote("Focus did not reach the camera.") }
    }
    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) =
        startTracking(TrackingBox((x - width / 2).toDouble(), (y - height / 2).toDouble(), width.toDouble(), height.toDouble()))
    fun startTracking(box: TrackingBox) {
        if (!can(CameraCapability.TRACKING)) return unavailable("Deep Track")
        if (box.isTooSmall) return presentControlNote("Frame Too Small")
        faceBox = null
        showTrack(LunaTrackBoxes(search = box))
        trackingRequest = box
        trackingRequestAt = SystemClock.elapsedRealtime()
        scope.launch {
            val left = box.x.coerceIn(0.0, 1.0)
            val top = box.y.coerceIn(0.0, 1.0)
            val ok = controls?.startTracking(left, top, minOf(box.width, 1 - left), minOf(box.height, 1 - top)) == true
            if (!ok) { showTrack(LunaTrackBoxes()); presentControlNote("Deep Track did not start.") }
        }
    }
    fun cancelSubjectTracking() = cancelTracking()
    fun cancelTracking() {
        if (!trackBoxes.active) return
        trackingRequest = null
        showTrack(LunaTrackBoxes())
        scope.launch { controls?.stopTracking() }
    }
    fun handleGamepadAction(action: GamepadOperatorAction) {
        when (action) {
            GamepadOperatorAction.RECORD -> if (!_controlBusy.value) pressShutter()
            GamepadOperatorAction.RECENTER -> performGimbalDoubleTap()
            GamepadOperatorAction.FLIP -> flipGimbal()
            GamepadOperatorAction.TRACK -> handleGamepadTrackToggle()
            GamepadOperatorAction.ZOOM_CHIP_IN -> setZoom(CamFov.nextJump(zoomCycleFrom(), zoomStops()))
            GamepadOperatorAction.ZOOM_CHIP_OUT -> setZoom(CamFov.previousJump(zoomCycleFrom(), zoomStops()))
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
        val moving = stickJob?.isActive == true
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
        if (!FaceTrackHold.shouldDrop(FaceTrackHold.secondsSinceHit(lastFaceHitAt, now), stickJob?.isActive == true)) return
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

    // Camera media: MediaLibraryController drives [media]; these hold the browse state.
    private var mediaOwner = 0L
    fun markBrowsingMedia(browsing: Boolean, resumePending: Boolean = false): Long {
        isBrowsingMedia = browsing
        return ++mediaOwner
    }
    fun ownsMediaLiveResume(owner: Long): Boolean = owner == mediaOwner
    /** DJI suspends its live-only Selfie Flip GET here; the Luna pauses live view through [media] instead. */
    fun setMediaTransportBrowsing(browsing: Boolean) = Unit
    suspend fun withMediaLiveResumeOwner(owner: Long, work: suspend () -> Unit) { if (ownsMediaLiveResume(owner)) work() }
    fun mediaLiveResumeExhausted(owner: Long) = Unit
    fun setOperatorOverlayHeld(held: Boolean) = Unit
    fun restartLiveViewAfterMedia(): Boolean = false
    fun beginMediaBrowse() { isBrowsingMedia = true }
    fun endMediaBrowse() { isBrowsingMedia = false }
    fun listMedia() = Unit
    // Luna deletes by URI through MediaLibraryController; favorites stay local like the official app.
    fun deleteMedia(handle: Int) = Unit
    fun setMediaFavorite(handle: Int, favorite: Boolean) = Unit

    // White balance: kelvin 2000...10000 or auto; the Luna has no tint.
    fun setWhiteBalanceAuto(tint: Int? = null) {
        if (canSendControl()) submitSetting(SettingValue.WhiteBalance(WhiteBalanceValue.Auto), "WB Auto")
    }
    fun setWhiteBalance(kelvin: Int, tint: Int) {
        if (!canSendControl()) return
        // fw 1.1.15 applies kelvin 3.5 to 3.9 s after the SET; the session waits for the readback.
        val clamped = kelvin.coerceIn(2_000, 10_000)
        submitSetting(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(clamped)), "WB ${clamped}K")
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
        pins.faceMetering = pin(on, SystemClock.elapsedRealtime(), 6_000)
        _faceMetering.value = on
        // The usual read 0.4 s after the SET is too early for 46; read again before the pin lapses.
        sendControl(if (on) "Metering Face" else "Metering Matrix", onFail = { pins.faceMetering = null; _faceMetering.value = previous },
            onSuccess = { scope.launch { delay(5_200); controls?.requestSettingsRefresh() } }) {
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
        sendControl(CameraCommands.colorLabel(mode, profile = profile), onFail = { pins.color = null; _status.value = _status.value.copy(colorMode = previous) }) {
            setColorProfile(LunaShellMapping.colorProfile(mode))
        }
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
        // Angle mode is ours: keep the chosen degrees and rewrite 1/N for the new fps.
        CaptureLists.rematchShutterDenomAfterFps(
            usesAngle = OperatorPrefs.shutterUsesAngle(appContext),
            degrees = OperatorPrefs.shutterAngleDegrees(appContext),
            previousFps = previous.fps,
            nextFps = format.frameRate.fps,
            expoMode = previous.expoMode,
            currentDenom = previous.shutterDenom,
            available = previous.availableShutterDenoms,
        )?.let(::setShutterDenom)
        return true
    }
    fun setResolutionFps(res: Int, fpsIndex: Int): Boolean = VideoFormat.parse(res, fpsIndex)?.let(::setVideoFormat) ?: false
    // The Luna exposes no audio controls or level meters.
    fun setAudioChannel(value: Int) = Unit
    fun setVocalBoost(on: Boolean) = Unit
    fun setWindNr(on: Boolean) = Unit
    fun setDirectionalAudio(mode: Int) = Unit
    fun refreshAudio() = Unit

    companion object {
        /** fw 1.1.15 official presets, same as iOS `LunaShellMapping.zoomChips`; the ceiling is appended when larger. */
        val LUNA_ZOOM_CHIPS = listOf(1.0, 2.0, 3.0, 6.0, 15.0)
        /** Capture to phone delay of a live frame at best (official-app captures: 90 to 200 ms after its stamp). */
        const val FRAME_LATENCY_MS = 90L
        /** iOS `GimbalStick.doubleTapWindow` (0.35 s) for the feed double tap to Deep Track. */
        const val DOUBLE_TAP_WINDOW_MS = 350L
    }
}

private fun hexBytes(bytes: ByteArray): String = bytes.joinToString(" ") { "%02x".format(it.toInt() and 0xFF) }

internal fun phaseAllowsReconnect(phase: ConnectionPhase): Boolean =
    when (phase) {
        ConnectionPhase.IDLE,
        ConnectionPhase.SCANNING,
        ConnectionPhase.FAILED,
        ConnectionPhase.LIVE,
        -> true
        else -> false
    }

/**
 * Live-feed stall detector. UDP receive age is the stall signal — never 1 Hz `0x09/0xa8`.
 * Mirrors iOS `FeedWatchdog` + `CameraSoftAP` first-picture gates.
 */
internal object LiveViewEnablePolicy {
    const val STALL_MS = 2_000L
    const val ESCALATE_MS = 5_000L
    const val GOP_GRACE_MS = 8_000L
    /** Endpoint repair and decoder-rebuild picture deadline. Matches iOS 16 s. */
    const val ENDPOINT_PICTURE_GRACE_MS = 16_000L
    /** Core `enableAnswerWindow`: an unanswered encoder-pause enable escalates after this. */
    const val ENABLE_ANSWER_MS = 1_500L
    /** Core `keyframeResendInterval` / `keyframeRequestLimit` for the decoder repair. */
    const val KEYFRAME_RESEND_MS = 2_000L
    const val KEYFRAME_REQUEST_LIMIT = 2
    /** Core `maxHeldRepairCycles`: repair deadlines (~60 s) before BLE recovery may run. */
    const val MAX_HELD_REPAIR_CYCLES = 3
    const val REBUILD_BACKOFF_MS = 60_000L
    const val COOLDOWN_MS = 15_000L
    const val REBUILD_COOLDOWN_MS = 5_000L
    const val ANALOG_LIFT_STALE_MS = 1_600L
    const val COMMAND_TIMEOUT_WINDOW_MS = 5_000L
    const val COMMAND_TIMEOUT_REBUILD_COUNT = 2
    const val FIRST_PICTURE_RESEND_MS = 2_000L
    const val FORMAT_POKE_MIN_SETTLE_MS = 800L
    const val FORMAT_STALL_MS = 2_000L
    const val HANDSHAKE_RETRY_PAUSE_MS = 500L
    const val HANDSHAKE_OPEN_RETRY_LIMIT = 6
    const val HANDSHAKE_REBIND_LIMIT = 3
    const val HANDSHAKE_SENDS_PER_BIND = 20
    const val HANDSHAKE_SEND_INTERVAL_MS = 350L
    /**
     * One `DatalinkDriver.open` budget: 20×350 ms × (1+3 rebinds) + 500 ms
     * pauses, plus headroom. iOS has no envelope; 30 s raced the last rebind.
     */
    fun handshakeOpenTimeoutMs(): Long =
        HANDSHAKE_SENDS_PER_BIND * HANDSHAKE_SEND_INTERVAL_MS * (HANDSHAKE_REBIND_LIMIT + 1L) +
            HANDSHAKE_RETRY_PAUSE_MS * HANDSHAKE_REBIND_LIMIT +
            5_000L
    /** After a foreground rebuild, wait this long for an IDR before a full rejoin. */
    const val FOREGROUND_PICTURE_GRACE_MS = GOP_GRACE_MS

    private fun coreDecision(kind: String, json: String): String? {
        if (!SwiftCore.isAvailable) return null
        return SwiftCore.cameraSoftAPDecision(kind, json)?.takeIf { it.isNotEmpty() }
    }

    private fun coreFlag(kind: String, json: String, fallback: () -> Boolean): Boolean =
        when (coreDecision(kind, json)) {
            "true" -> true
            "false" -> false
            else -> fallback()
        }

    private fun secJson(ms: Long?): String = ms?.let { (it / 1000.0).toString() } ?: "null"

    fun shouldGiveUpOpenRetry(attempts: Int): Boolean =
        coreFlag("shouldGiveUpOpenRetry", "{\"attempts\":$attempts}") {
            attempts >= HANDSHAKE_OPEN_RETRY_LIMIT
        }

    fun shouldKickAfterHandshakeTimeout(pathReady: Boolean): Boolean =
        coreFlag("shouldKickAfterHandshakeTimeout", "{\"pathReady\":$pathReady}") { !pathReady }

    fun canSendHandshake(receiveArmed: Boolean, connectionReady: Boolean): Boolean =
        coreFlag(
            "canSendHandshake",
            "{\"receiveArmed\":$receiveArmed,\"connectionReady\":$connectionReady}",
        ) { receiveArmed && connectionReady }

    enum class Action { NONE, RESEND_ENABLE, REBUILD_DECODER, REBUILD_UDP, FULL_REJOIN }

    enum class Stage { IDLE, RESEND_ENABLE, REBUILD_DECODER, REBUILD_UDP, FULL_REJOIN, COOLDOWN }

    enum class FirstPictureStep {
        WAIT,
        RESEND_ENABLE,
        POKE_RECORDING_FORMAT,
        REBUILD_UDP,
        REJOIN,
    }

    class State {
        var stage: Stage = Stage.IDLE
        var lastActionAt: Long = 0
        var encoderPauseEnables: Int = 0

        fun reset() {
            stage = Stage.IDLE
            lastActionAt = 0
            encoderPauseEnables = 0
        }

        fun capture(): State {
            val copy = State()
            copy.restore(this)
            return copy
        }

        fun restore(other: State) {
            stage = other.stage
            lastActionAt = other.lastActionAt
            encoderPauseEnables = other.encoderPauseEnables
        }
    }

    data class Snapshot(
        val now: Long,
        val videoPackets: Int,
        val lastVideoPacketAt: Long?,
        val lastAccessUnitAt: Long?,
        val lastStatusAt: Long?,
        val lastBleNotifyAt: Long?,
        val lastRebuildAt: Long?,
        val lastEnableAt: Long,
        val pathReady: Boolean,
        val hasFormat: Boolean,
        val decoderErrors: Int,
        val live: Boolean,
        val sawPicture: Boolean,
        val lastFocusTrackAt: Long? = null,
        val lastZoomAt: Long? = null,
        val zoomPinchActive: Boolean = false,
        val lastGimbalThrowAt: Long? = null,
        val gimbalStickHeld: Boolean = false,
        val hadVideo: Boolean? = null,
        val lastCameraSetAt: Long? = null,
        val lastDecoderOutputAt: Long? = null,
        val lastPresentedAt: Long? = null,
        val decoderOutputExpected: Boolean = false,
        val referenceRecoveryNeeded: Boolean = false,
        val lastIrapAt: Long? = null,
        val repairReady: Boolean = true,
    )

    fun age(now: Long, at: Long?): Long? = at?.let { now - it }

    fun udpReceiveAlive(snap: Snapshot): Boolean {
        val video = age(snap.now, snap.lastVideoPacketAt)
        if (video != null && video < STALL_MS) return true
        val au = age(snap.now, snap.lastAccessUnitAt)
        return au != null && au < STALL_MS
    }

    fun controlReceiveAlive(snap: Snapshot): Boolean {
        val status = age(snap.now, snap.lastStatusAt) ?: return false
        return status < STALL_MS
    }

    fun hadVideo(videoPackets: Int, videoAgeMs: Long?): Boolean =
        videoPackets > 0 || videoAgeMs != null

    fun shouldHoldForGopReset(sinceEnableMs: Long?, videoAgeMs: Long?): Boolean =
        coreFlag(
            "shouldHoldForGOPReset",
            "{\"secondsSinceLastEnable\":${secJson(sinceEnableMs)},\"lastVideoPacketAge\":${secJson(videoAgeMs)}}",
        ) {
            if (sinceEnableMs == null || sinceEnableMs >= GOP_GRACE_MS) return@coreFlag false
            if (videoAgeMs != null && videoAgeMs > sinceEnableMs + STALL_MS) return@coreFlag false
            true
        }

    /** Control Center / a short app-switcher peek still has a live GOP — do not tear UDP. */
    fun shouldRecoverAfterForeground(
        secondsSinceLastPresented: Double?,
        videoFresh: Boolean = false,
        statusFresh: Boolean = false,
        stallSec: Double = STALL_MS / 1000.0,
    ): Boolean =
        coreFlag(
            "shouldRecoverAfterForeground",
            "{\"secondsSinceLastPresented\":${secondsSinceLastPresented ?: "null"},\"videoFresh\":$videoFresh,\"statusFresh\":$statusFresh}",
        ) {
            if (videoFresh || statusFresh) return@coreFlag false
            val age = secondsSinceLastPresented ?: return@coreFlag true
            age >= stallSec
        }

    fun shouldEscalateForegroundRecover(
        secondsSinceLastPresented: Double?,
        videoFresh: Boolean = false,
        statusFresh: Boolean = false,
        graceSec: Double = FOREGROUND_PICTURE_GRACE_MS / 1000.0,
    ): Boolean =
        coreFlag(
            "shouldEscalateForegroundRecover",
            "{\"secondsSinceLastPresented\":${secondsSinceLastPresented ?: "null"},\"videoFresh\":$videoFresh,\"statusFresh\":$statusFresh}",
        ) {
            if (videoFresh || statusFresh) return@coreFlag false
            val age = secondsSinceLastPresented ?: return@coreFlag true
            age >= graceSec
        }

    enum class HandshakeTimeoutStep { KEEP_SOCKET, REBIND_UDP, FAIL }

    fun handshakeTimeoutStep(
        pathReady: Boolean,
        rebindsUsed: Int,
        inboundDatagrams: Int = 0,
        rebindLimit: Int = HANDSHAKE_REBIND_LIMIT,
    ): HandshakeTimeoutStep {
        when (
            coreDecision(
                "handshakeTimeoutStep",
                "{\"pathReady\":$pathReady,\"rebindsUsed\":$rebindsUsed,\"inboundDatagrams\":$inboundDatagrams,\"rebindLimit\":$rebindLimit}",
            )
        ) {
            "keepSocket" -> return HandshakeTimeoutStep.KEEP_SOCKET
            "rebindUDP" -> return HandshakeTimeoutStep.REBIND_UDP
            "fail" -> return HandshakeTimeoutStep.FAIL
        }
        if (inboundDatagrams > 0) return HandshakeTimeoutStep.KEEP_SOCKET
        if (!pathReady) return HandshakeTimeoutStep.FAIL
        if (rebindsUsed < rebindLimit) return HandshakeTimeoutStep.REBIND_UDP
        return HandshakeTimeoutStep.FAIL
    }

    fun holdUdpRebuildGopLog(sinceEnableMs: Long?, videoAgeMs: Long?): String =
        "feed: hold UDP rebuild — GOP-reset grace lastEnable=${ageSec(sinceEnableMs)}s lastVideo=${ageSec(videoAgeMs)}s"

    fun holdUdpRebuildAfcLog(sinceSetMs: Long?, videoAgeMs: Long?): String =
        "feed: hold UDP rebuild — AF-C grace lastSet=${ageSec(sinceSetMs)}s lastVideo=${ageSec(videoAgeMs)}s"

    fun holdUdpRebuildZoomLog(sinceSetMs: Long?, videoAgeMs: Long?): String =
        "feed: hold UDP rebuild — zoom grace lastSet=${ageSec(sinceSetMs)}s lastVideo=${ageSec(videoAgeMs)}s"

    private fun ageSec(ageMs: Long?): String {
        val value = if (ageMs == null) -1.0 else ageMs / 1000.0
        return String.format(java.util.Locale.US, "%.1f", value)
    }

    fun shouldHoldBind(pathReady: Boolean, bleAgeMs: Long?): Boolean =
        pathReady && (bleAgeMs ?: Long.MAX_VALUE) < STALL_MS

    fun shouldHoldRebuildAfterRecentUdp(
        sinceRebuildMs: Long?,
        pathReady: Boolean,
        bleAgeMs: Long?,
        hadVideo: Boolean,
    ): Boolean {
        if (!hadVideo) return false
        if (!shouldHoldBind(pathReady, bleAgeMs)) return false
        val since = sinceRebuildMs ?: return false
        return since < REBUILD_BACKOFF_MS
    }

    fun enableRestartedVideo(sinceEnableMs: Long?, videoAgeMs: Long?): Boolean {
        if (sinceEnableMs == null || videoAgeMs == null) return false
        return videoAgeMs + 50 < sinceEnableMs
    }

    fun shouldTreatLiveVideoAsStale(
        lastVideoPacketAgeMs: Long?,
        hadVideo: Boolean,
        recovering: Boolean = false,
    ): Boolean =
        coreFlag(
            "shouldTreatLiveVideoAsStale",
            "{\"lastVideoPacketAge\":${secJson(lastVideoPacketAgeMs)},\"hadVideo\":$hadVideo,\"recovering\":$recovering}",
        ) {
            if (recovering) return@coreFlag true
            val age = lastVideoPacketAgeMs ?: return@coreFlag hadVideo
            age >= ANALOG_LIFT_STALE_MS
        }

    fun shouldStartFeedRecovery(rebuildInFlight: Boolean): Boolean =
        coreFlag("shouldStartFeedRecovery", "{\"rebuildInFlight\":$rebuildInFlight}") {
            !rebuildInFlight
        }

    enum class DecoderRepairStep { WAIT, RESEND_KEYFRAME, REBUILD_ENDPOINT, DEADLINE }

    /** Core `FeedWatchdog.decoderRepairStep`: resend until answered, then the endpoint. */
    fun decoderRepairStep(
        sinceRepairStartMs: Long,
        sinceEnableMs: Long,
        sinceIrapMs: Long?,
        keyframeRequests: Int,
    ): DecoderRepairStep {
        val core =
            coreDecision(
                "decoderRepairStep",
                "{\"secondsSinceRepairStart\":${sinceRepairStartMs / 1000.0}," +
                    "\"secondsSinceLastEnable\":${sinceEnableMs / 1000.0}," +
                    "\"secondsSinceLastIrap\":${secJson(sinceIrapMs)}," +
                    "\"keyframeRequests\":$keyframeRequests}",
            )
        return when (core) {
            "wait" -> DecoderRepairStep.WAIT
            "resendKeyframe" -> DecoderRepairStep.RESEND_KEYFRAME
            "rebuildEndpoint" -> DecoderRepairStep.REBUILD_ENDPOINT
            "deadline" -> DecoderRepairStep.DEADLINE
            else -> {
                if (sinceRepairStartMs >= ENDPOINT_PICTURE_GRACE_MS) return DecoderRepairStep.DEADLINE
                val answered = sinceIrapMs != null && sinceIrapMs < sinceEnableMs
                if (answered || sinceEnableMs < KEYFRAME_RESEND_MS) return DecoderRepairStep.WAIT
                if (keyframeRequests < KEYFRAME_REQUEST_LIMIT) DecoderRepairStep.RESEND_KEYFRAME
                else DecoderRepairStep.REBUILD_ENDPOINT
            }
        }
    }

    /**
     * Core `FeedWatchdog.nextSessionHoldCycles`: no BLE teardown while video arrives,
     * for at most [MAX_HELD_REPAIR_CYCLES] repair deadlines per episode. 0 releases.
     */
    fun nextSessionHoldCycles(videoAgeMs: Long?, previousCycles: Int, pictureSinceLastCycle: Boolean): Int {
        val core =
            coreDecision(
                "nextSessionHoldCycles",
                "{\"lastVideoPacketAge\":${secJson(videoAgeMs)},\"previousCycles\":$previousCycles," +
                    "\"pictureSinceLastCycle\":$pictureSinceLastCycle}",
            )?.toIntOrNull()
        if (core != null) return core
        val cycles = (if (pictureSinceLastCycle) 0 else maxOf(0, previousCycles)) + 1
        val videoLive = videoAgeMs != null && videoAgeMs < STALL_MS
        return if (videoLive && cycles < MAX_HELD_REPAIR_CYCLES) cycles else 0
    }

    fun shouldRepeatRecoverEnable(
        sinceEnableMs: Long,
        @Suppress("UNUSED_PARAMETER") sinceRebuildMs: Long?,
        @Suppress("UNUSED_PARAMETER") pathReady: Boolean,
        @Suppress("UNUSED_PARAMETER") bleAgeMs: Long?,
        hadVideo: Boolean,
        @Suppress("UNUSED_PARAMETER") holdEnableCount: Int,
        @Suppress("UNUSED_PARAMETER") videoAgeMs: Long?,
    ): Boolean =
        coreFlag(
            "shouldRepeatRecoverEnable",
            "{" +
                "\"secondsSinceLastEnable\":${sinceEnableMs / 1000.0}," +
                "\"secondsSinceLastRebuild\":${secJson(sinceRebuildMs)}," +
                "\"pathReady\":$pathReady," +
                "\"lastBleNotifyAge\":${secJson(bleAgeMs)}," +
                "\"hadVideo\":$hadVideo" +
                "}",
        ) {
            // Mid-session extra enable GOP-cuts. FeedWatchdog.tick owns that ladder.
            if (hadVideo) return@coreFlag false
            sinceEnableMs >= STALL_MS
        }

    fun shouldRebuildAfterCommandTimeouts(
        timeoutsInWindow: Int,
        downlinkFresh: Boolean,
        videoFresh: Boolean,
        rebuildInFlight: Boolean,
        sinceRebuildMs: Long?,
        statusFresh: Boolean = false,
    ): Boolean =
        coreFlag(
            "shouldRebuildAfterCommandTimeouts",
            "{" +
                "\"timeoutsInWindow\":$timeoutsInWindow," +
                "\"downlinkFresh\":$downlinkFresh," +
                "\"videoFresh\":$videoFresh," +
                "\"rebuildInFlight\":$rebuildInFlight," +
                "\"secondsSinceLastRebuild\":${secJson(sinceRebuildMs)}," +
                "\"statusFresh\":$statusFresh" +
                "}",
        ) {
            if (videoFresh) return@coreFlag false
            if (statusFresh) return@coreFlag false
            if (timeoutsInWindow < COMMAND_TIMEOUT_REBUILD_COUNT || !downlinkFresh || rebuildInFlight) {
                return@coreFlag false
            }
            if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) return@coreFlag false
            true
        }

    fun shouldRunFirstPictureRecover(presentedAgeMs: Long?, alreadySettled: Boolean): Boolean =
        coreFlag(
            "shouldRunFirstPictureRecover",
            "{\"secondsSinceLastPresented\":${secJson(presentedAgeMs)},\"alreadySettled\":$alreadySettled}",
        ) {
            if (alreadySettled) return@coreFlag false
            presentedAgeMs == null || presentedAgeMs >= STALL_MS
        }

    fun shouldDeferRecordingFormatPoke(
        hasKnownRecordingFormat: Boolean,
        sinceEnableMs: Long,
    ): Boolean =
        coreFlag(
            "shouldDeferRecordingFormatPoke",
            "{" +
                "\"hasKnownRecordingFormat\":$hasKnownRecordingFormat," +
                "\"secondsSinceLastEnable\":${sinceEnableMs / 1000.0}" +
                "}",
        ) { !hasKnownRecordingFormat && sinceEnableMs < GOP_GRACE_MS }

    fun shouldMarkFirstPictureSettled(presentedAgeMs: Long?, sinceEnableMs: Long): Boolean =
        coreFlag(
            "shouldMarkFirstPictureSettled",
            "{\"secondsSinceLastPresented\":${secJson(presentedAgeMs)},\"secondsSinceLastEnable\":${sinceEnableMs / 1000.0}}",
        ) {
            val presented = presentedAgeMs ?: return@coreFlag false
            presented >= 0 && presented < STALL_MS
        }

    fun shouldBeginIDRHoldOnEnable(hasPresentedPicture: Boolean): Boolean =
        coreFlag(
            "shouldBeginIDRHoldOnEnable",
            "{\"hasPresentedPicture\":$hasPresentedPicture}",
        ) { !hasPresentedPicture }

    fun shouldReleaseIDRHold(
        awaitingIDR: Boolean,
        udpReceiveAlive: Boolean,
        sinceEnableMs: Long?,
        hasPresentedPicture: Boolean,
    ): Boolean =
        coreFlag(
            "shouldReleaseIDRHold",
            "{" +
                "\"awaitingIDR\":$awaitingIDR," +
                "\"udpReceiveAlive\":$udpReceiveAlive," +
                "\"secondsSinceLastEnable\":${secJson(sinceEnableMs)}," +
                "\"hasPresentedPicture\":$hasPresentedPicture" +
                "}",
        ) {
            if (!awaitingIDR || !udpReceiveAlive || !hasPresentedPicture) return@coreFlag false
            val since = sinceEnableMs ?: return@coreFlag false
            since >= GOP_GRACE_MS
        }

    fun firstPictureStep(
        videoPackets: Int,
        enableSends: Int,
        sinceEnableMs: Long,
        videoAgeMs: Long?,
        sinceRebuildMs: Long?,
        needsRecordingFormatPoke: Boolean = false,
        alreadyPokedRecordingFormat: Boolean = false,
        recordingFormatPokeInFlight: Boolean = false,
        isRecording: Boolean = false,
        hasPresentedPicture: Boolean = false,
    ): FirstPictureStep {
        when (
            coreDecision(
                "firstPictureStep",
                "{" +
                    "\"videoPackets\":$videoPackets," +
                    "\"enableSends\":$enableSends," +
                    "\"secondsSinceLastEnable\":${sinceEnableMs / 1000.0}," +
                    "\"secondsSinceLastVideo\":${secJson(videoAgeMs)}," +
                    "\"secondsSinceLastRebuild\":${secJson(sinceRebuildMs)}," +
                    "\"needsRecordingFormatPoke\":$needsRecordingFormatPoke," +
                    "\"alreadyPokedRecordingFormat\":$alreadyPokedRecordingFormat," +
                    "\"recordingFormatPokeInFlight\":$recordingFormatPokeInFlight," +
                    "\"isRecording\":$isRecording," +
                    "\"hasPresentedPicture\":$hasPresentedPicture" +
                    "}",
            )
        ) {
            "wait" -> return FirstPictureStep.WAIT
            "resendEnable" -> return FirstPictureStep.RESEND_ENABLE
            "pokeRecordingFormat" -> return FirstPictureStep.POKE_RECORDING_FORMAT
            "rebuildUDP" -> return FirstPictureStep.REBUILD_UDP
            "rejoin" -> return FirstPictureStep.REJOIN
        }
        if (hasPresentedPicture) return FirstPictureStep.WAIT
        if (enableSends < 1) return FirstPictureStep.RESEND_ENABLE
        if (recordingFormatPokeInFlight) return FirstPictureStep.WAIT
        if (sinceEnableMs < FIRST_PICTURE_RESEND_MS) return FirstPictureStep.WAIT
        val had = hadVideo(videoPackets, videoAgeMs)
        if (shouldPokeRecordingFormat(
                needsPoke = needsRecordingFormatPoke,
                alreadyPoked = alreadyPokedRecordingFormat,
                isRecording = isRecording,
                hadVideo = had,
                enableSends = enableSends,
                sinceEnableMs = sinceEnableMs,
            )
        ) {
            return FirstPictureStep.POKE_RECORDING_FORMAT
        }
        val videoFresh = had && (videoAgeMs ?: Long.MAX_VALUE) < STALL_MS
        if (!had) {
            if (sinceEnableMs < GOP_GRACE_MS) return FirstPictureStep.WAIT
            if (enableSends >= 4) return FirstPictureStep.REJOIN
            if (enableSends >= 2) {
                if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) {
                    return FirstPictureStep.WAIT
                }
                return FirstPictureStep.REBUILD_UDP
            }
            return FirstPictureStep.RESEND_ENABLE
        }
        if (sinceEnableMs < GOP_GRACE_MS) {
            if (videoFresh && enableSends == 1 && sinceEnableMs >= ESCALATE_MS) {
                return FirstPictureStep.RESEND_ENABLE
            }
            return FirstPictureStep.WAIT
        }
        if (videoFresh) {
            if (enableSends == 1) return FirstPictureStep.RESEND_ENABLE
            // Match CameraSoftAP: fresh P-frames cannot keep a missed first IRAP
            // waiting forever after the one resend. The rejoin owner is bounded.
            if (sinceEnableMs >= ENDPOINT_PICTURE_GRACE_MS) return FirstPictureStep.REJOIN
            return FirstPictureStep.WAIT
        }
        if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) return FirstPictureStep.WAIT
        if (enableSends >= 4) return FirstPictureStep.REJOIN
        if (sinceRebuildMs != null) return FirstPictureStep.REJOIN
        return FirstPictureStep.REBUILD_UDP
    }

    /** Pocket 3: SET 1080 then boot 4K before tearing UDP. Not Pocket 4. */
    fun shouldPokeRecordingFormat(
        needsPoke: Boolean,
        alreadyPoked: Boolean,
        isRecording: Boolean,
        hadVideo: Boolean,
        enableSends: Int,
        sinceEnableMs: Long,
    ): Boolean =
        coreFlag(
            "shouldPokeRecordingFormat",
            "{" +
                "\"needsPoke\":$needsPoke," +
                "\"alreadyPoked\":$alreadyPoked," +
                "\"isRecording\":$isRecording," +
                "\"hadVideo\":$hadVideo," +
                "\"enableSends\":$enableSends," +
                "\"secondsSinceLastEnable\":${sinceEnableMs / 1000.0}" +
                "}",
        ) {
            if (!needsPoke || alreadyPoked || isRecording || enableSends < 1) return@coreFlag false
            if (sinceEnableMs < FIRST_PICTURE_RESEND_MS) return@coreFlag false
            if (!hadVideo) return@coreFlag true
            sinceEnableMs >= ESCALATE_MS
        }

    /**
     * Leftover TRAIL P-frames still arriving: ask for IDR, keep the socket.
     * [videoPackets] > 0 with a stale [videoAgeMs] is a dead receive — rebuild UDP.
     * Frozen pkts=375 then three enable resends delayed first picture ~32 s.
     */
    fun shouldKeepUdpForLeftoverGop(
        noPicture: Boolean,
        videoPackets: Int,
        videoAgeMs: Long?,
    ): Boolean {
        if (!noPicture || videoPackets <= 0) return false
        val age = videoAgeMs ?: return false
        return age < STALL_MS
    }

    fun shouldIngestLiveVideo(ingestArmed: Boolean): Boolean = ingestArmed

    /**
     * Settings / media covering the monitor is not a leftover-GOP gate.
     * Dropping `0x02` while UDP stays live blacks the well on return (#177).
     */
    fun shouldIngestLiveVideo(
        ingestArmed: Boolean,
        browsingMedia: Boolean,
        operatorOverlayHeld: Boolean,
    ): Boolean {
        // browsingMedia / operatorOverlayHeld are lockstep with CameraSoftAP.
        // Overlay/browse must not drop 0x02. Pocket has no periodic GOP (#177).
        if (browsingMedia || operatorOverlayHeld) return ingestArmed
        return ingestArmed
    }

    /** Pocket: `0x02/0x68` `08` immediately before `0x09/0xa8`. Not Nano. */
    fun shouldSendLiveViewPrepare(usesNanoLiveViewGate: Boolean): Boolean =
        coreFlag(
            "shouldSendLiveViewPrepare",
            "{\"usesNanoLiveViewGate\":$usesNanoLiveViewGate}",
        ) { !usesNanoLiveViewGate }

    /** `0x02/0x0c` is gallery enter/exit — not live-start. Matches iOS / handbook. */
    fun shouldExitPlaybackBeforeLiveEnable(inPlayback: Boolean): Boolean =
        coreFlag("shouldExitPlaybackBeforeLiveEnable", "{\"inPlayback\":$inPlayback}") { inPlayback }

    fun shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: Boolean): Boolean =
        coreFlag(
            "shouldClearForegroundRecoverWithoutRebuild",
            "{\"holdsMonitor\":$holdsMonitor}",
        ) { holdsMonitor }

    fun shouldContinueFirstPictureAfterStrayPlayback(hasPicture: Boolean): Boolean =
        coreFlag(
            "shouldContinueFirstPictureAfterStrayPlayback",
            "{\"hasPicture\":$hasPicture}",
        ) { !hasPicture }

    fun shouldKeepaliveRebuildUDP(
        flowNeedsRebuild: Boolean,
        rebuildInFlight: Boolean,
        sinceRebuildMs: Long?,
        videoFresh: Boolean = false,
        sawPicture: Boolean = true,
        statusFresh: Boolean = false,
        sinceEnableMs: Long? = null,
        pathReady: Boolean = true,
    ): Boolean =
        coreFlag(
            "shouldKeepaliveRebuildUDP",
            "{" +
                "\"flowNeedsRebuild\":$flowNeedsRebuild," +
                "\"rebuildInFlight\":$rebuildInFlight," +
                "\"secondsSinceLastRebuild\":${secJson(sinceRebuildMs)}," +
                "\"videoFresh\":$videoFresh," +
                "\"sawPicture\":$sawPicture," +
                "\"statusFresh\":$statusFresh," +
                "\"secondsSinceLastEnable\":${secJson(sinceEnableMs)}," +
                "\"pathReady\":$pathReady" +
                "}",
        ) {
            if (!sawPicture) return@coreFlag false
            if (!pathReady) return@coreFlag false
            if (!flowNeedsRebuild || rebuildInFlight || videoFresh) return@coreFlag false
            if (statusFresh) return@coreFlag false
            if (shouldHoldForGopReset(sinceEnableMs, null)) return@coreFlag false
            if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) return@coreFlag false
            true
        }

    fun shouldForceEnableAfterUDPRebuild(hadVideo: Boolean): Boolean =
        coreFlag("shouldForceEnableAfterUDPRebuild", "{\"hadVideo\":$hadVideo}") { !hadVideo }

    fun shouldRearmLiveIngestAfterUDPRebuild(wasAccepting: Boolean): Boolean =
        coreFlag(
            "shouldRearmLiveIngestAfterUDPRebuild",
            "{\"wasAccepting\":$wasAccepting}",
        ) { wasAccepting }

    fun shouldSendRecoverEnable(pathReady: Boolean, decoderReady: Boolean): Boolean =
        coreFlag(
            "shouldSendRecoverEnable",
            "{\"pathReady\":$pathReady,\"decoderReady\":$decoderReady}",
        ) { pathReady && decoderReady }

    fun shouldCommitLiveHandshake(
        driverOwned: Boolean,
        isClosed: Boolean,
        isCancelled: Boolean,
    ): Boolean =
        coreFlag(
            "shouldCommitLiveHandshake",
            "{\"driverOwned\":$driverOwned,\"isClosed\":$isClosed,\"isCancelled\":$isCancelled}",
        ) { driverOwned && !isClosed && !isCancelled }

    fun shouldReuseDatalink(isClosed: Boolean): Boolean =
        coreFlag("shouldReuseDatalink", "{\"isClosed\":$isClosed}") { !isClosed }

    /** Match the portable watchdog: upstream progress cannot renew a downstream stall. */
    private fun shouldHoldForControlGrace(snap: Snapshot, stalledStageAge: Long?): Boolean {
        val stageAgeSec = stalledStageAge?.div(1000.0)
        fun withinGrace(graceSec: Double): Boolean =
            stageAgeSec == null || stageAgeSec < STALL_MS / 1000.0 + graceSec
        return CameraCommands.shouldHoldCameraSetWatchdog(
            age(snap.now, snap.lastCameraSetAt)?.div(1000.0), stageAgeSec,
        ) || (withinGrace(FocusTrackMode.VIDEO_GRACE_SEC) &&
            FocusTrackMode.shouldHoldWatchdog(age(snap.now, snap.lastFocusTrackAt)?.div(1000.0))) ||
            snap.zoomPinchActive ||
            (withinGrace(CamFov.VIDEO_GRACE_SEC) &&
                CamFov.shouldHoldWatchdog(age(snap.now, snap.lastZoomAt)?.div(1000.0))) ||
            CameraCommands.shouldHoldGimbalWatchdog(
                age(snap.now, snap.lastGimbalThrowAt)?.div(1000.0), stageAgeSec, snap.gimbalStickHeld,
            )
    }

    fun tick(state: State, snap: Snapshot): Action {
        if (!snap.live) {
            state.reset()
            return Action.NONE
        }
        if (!snap.pathReady || !snap.repairReady) return Action.NONE

        val outputAt = snap.lastDecoderOutputAt ?: snap.lastPresentedAt
        val outputAge = age(snap.now, outputAt) ?: 0L
        val decoderSilent =
            snap.decoderOutputExpected && snap.sawPicture && outputAge >= STALL_MS
        val knownReferenceLoss =
            snap.decoderOutputExpected && snap.sawPicture && snap.referenceRecoveryNeeded
        val decoderNeedsRepair = decoderSilent || knownReferenceLoss
        val presentedAge = age(snap.now, snap.lastPresentedAt) ?: 0L
        val auAge = age(snap.now, snap.lastAccessUnitAt)
        val assemblyStalled =
            snap.sawPicture &&
                udpReceiveAlive(snap) &&
                auAge != null &&
                auAge >= STALL_MS &&
                presentedAge >= STALL_MS &&
                (!snap.decoderOutputExpected || decoderSilent)
        // An early loss repair must not accept still-young pre-action output,
        // or IRAP submission without output, as completion of its deadline.
        val outputAfterAction = outputAt != null && outputAt > state.lastActionAt
        if (state.stage == Stage.REBUILD_DECODER && (decoderNeedsRepair || !outputAfterAction)) {
            if (snap.now - state.lastActionAt >= ENDPOINT_PICTURE_GRACE_MS) {
                return fire(state, Action.FULL_REJOIN, snap.now)
            }
            return Action.NONE
        }

        val sinceEnable = if (snap.lastEnableAt == 0L) null else snap.now - snap.lastEnableAt
        val videoAge = age(snap.now, snap.lastVideoPacketAt)
        if (udpReceiveAlive(snap) && !assemblyStalled) {
            // Lost parameter sets are restored by this existing repair's enable.
            // Requiring format here strands an established decoder on inter-frames.
            if (decoderNeedsRepair &&
                (auAge ?: Long.MAX_VALUE) < STALL_MS
            ) {
                // Twin of FeedWatchdog: cooldown ends, and an IRAP after the last
                // enable answered it, so a new loss gets its own request.
                if ((state.stage == Stage.FULL_REJOIN || state.stage == Stage.COOLDOWN) &&
                    snap.now - state.lastActionAt < COOLDOWN_MS
                ) {
                    return Action.NONE
                }
                val irapAnsweredEnable =
                    snap.lastIrapAt != null && snap.lastEnableAt != 0L && snap.lastIrapAt > snap.lastEnableAt
                if (!irapAnsweredEnable && shouldHoldForGopReset(sinceEnable, videoAge)) return Action.NONE
                if (shouldHoldForControlGrace(snap, outputAge)) return Action.NONE
                return fire(state, Action.REBUILD_DECODER, snap.now)
            }
            state.reset()
            return Action.NONE
        }
        if (shouldHoldForGopReset(sinceEnable, videoAge)) return Action.NONE
        if (shouldHoldForControlGrace(snap, if (assemblyStalled) auAge else videoAge)) {
            return Action.NONE
        }

        val had = snap.hadVideo ?: hadVideo(snap.videoPackets, videoAge)
        if (!had) {
            if (state.stage != Stage.IDLE && snap.now - state.lastActionAt < ESCALATE_MS) {
                return Action.NONE
            }
            return when (state.stage) {
                Stage.IDLE -> fire(state, Action.RESEND_ENABLE, snap.now)
                Stage.RESEND_ENABLE -> fire(state, Action.REBUILD_UDP, snap.now)
                Stage.REBUILD_DECODER, Stage.REBUILD_UDP, Stage.FULL_REJOIN, Stage.COOLDOWN -> {
                    state.stage = Stage.COOLDOWN
                    state.lastActionAt = snap.now
                    Action.NONE
                }
            }
        }

        if (state.stage == Stage.FULL_REJOIN) {
            state.stage = Stage.COOLDOWN
            state.lastActionAt = snap.now
            return Action.NONE
        }

        if (assemblyStalled || (controlReceiveAlive(snap) && !udpReceiveAlive(snap))) {
            // Twin of FeedWatchdog: an unanswered enable escalates after ENABLE_ANSWER_MS.
            val rungWait = if (state.stage == Stage.RESEND_ENABLE) ENABLE_ANSWER_MS else ESCALATE_MS
            if (state.stage != Stage.IDLE && snap.now - state.lastActionAt < rungWait) {
                return Action.NONE
            }
            if (state.encoderPauseEnables < 1) {
                state.encoderPauseEnables += 1
                return fire(state, Action.RESEND_ENABLE, snap.now)
            }
            val bleAge = age(snap.now, snap.lastBleNotifyAt)
            val sinceRebuild = age(snap.now, snap.lastRebuildAt)
            if (shouldHoldRebuildAfterRecentUdp(sinceRebuild, snap.pathReady, bleAge, had)) {
                return Action.NONE
            }
            if (state.stage == Stage.REBUILD_UDP) {
                return fire(state, Action.FULL_REJOIN, snap.now)
            }
            return fire(state, Action.REBUILD_UDP, snap.now)
        }

        val bleAge = age(snap.now, snap.lastBleNotifyAt)
        val sinceRebuild = age(snap.now, snap.lastRebuildAt)
        if (shouldHoldRebuildAfterRecentUdp(sinceRebuild, snap.pathReady, bleAge, had)) {
            if (state.stage == Stage.IDLE) {
                state.stage = Stage.COOLDOWN
                state.lastActionAt = snap.now
            }
            return Action.NONE
        }

        if (state.stage == Stage.COOLDOWN) {
            if (shouldHoldBind(snap.pathReady, bleAge)) return Action.NONE
            if (snap.now - state.lastActionAt >= COOLDOWN_MS) {
                return fire(state, Action.REBUILD_UDP, snap.now)
            }
            return Action.NONE
        }

        if (state.stage != Stage.IDLE && snap.now - state.lastActionAt < ESCALATE_MS) {
            return Action.NONE
        }
        return when (state.stage) {
            Stage.IDLE, Stage.RESEND_ENABLE, Stage.REBUILD_DECODER ->
                fire(state, Action.REBUILD_UDP, snap.now)
            Stage.REBUILD_UDP -> fire(state, Action.FULL_REJOIN, snap.now)
            Stage.FULL_REJOIN, Stage.COOLDOWN -> {
                state.stage = Stage.COOLDOWN
                state.lastActionAt = snap.now
                Action.NONE
            }
        }
    }

    private fun fire(state: State, action: Action, now: Long): Action {
        state.stage =
            when (action) {
                Action.RESEND_ENABLE -> Stage.RESEND_ENABLE
                Action.REBUILD_DECODER -> Stage.REBUILD_DECODER
                Action.REBUILD_UDP -> Stage.REBUILD_UDP
                Action.FULL_REJOIN -> Stage.FULL_REJOIN
                Action.NONE -> state.stage
            }
        state.lastActionAt = now
        return action
    }
}
