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
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.feed.FacePriorityExposure
import com.opencapture.openpocketcine.feed.SerialSessionGate
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
import com.opencapture.openpocketcine.core.CameraControls
import com.opencapture.openpocketcine.core.CameraIdentity
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

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
class PocketCameraSession(context: Context, borrowing: HevcDecoder? = null) : CameraSessionSeam {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val backend: CameraBackend = MonitorConfiguration.createBackend(appContext)
    private val controls: CameraControls? = backend as? CameraControls
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

    val controlBusy: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
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

    // Programmed moves need a native pose readback the Luna does not report yet.
    val gimbalMoveCountdown: StateFlow<Int?> = MutableStateFlow<Int?>(null).asStateFlow()
    val gimbalMoveReadout: StateFlow<String> = MutableStateFlow("").asStateFlow()
    var gimbalRamp: GimbalRamp = GimbalRamp.OFF
    var gimbalDoubleTap: GimbalDoubleTap = GimbalDoubleTap.RECENTER
    val gimbalMode: StateFlow<GimbalMode> = MutableStateFlow(GimbalMode.FOLLOW).asStateFlow()
    val gimbalSpeed: StateFlow<GimbalSpeed> = MutableStateFlow(GimbalSpeed.DEFAULT).asStateFlow()
    val gimbalProgram: StateFlow<GimbalProgram> = MutableStateFlow(GimbalProgram()).asStateFlow()
    val gimbalMovePaused: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val gimbalMoveRunning: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val hasGimbal: Boolean get() = connectedCamera != null && can(CameraCapability.GIMBAL)
    val supportsZoom: Boolean get() = connectedCamera != null && can(CameraCapability.ZOOM)
    val canRunProgrammedMove: Boolean get() = false
    fun programmedZoomUnavailableReason(status: CameraStatus = _status.value): String? =
        "Programmed moves are not available on the Luna Ultra yet."
    fun gimbalDebugText(): String = "luna gimbal: rate stick only"
    fun predictedGimbalWaypoint(nowSeconds: Double): GimbalWaypoint? = null
    val liveGimbalWaypoint: GimbalWaypoint? get() = null

    var connectedCamera: FoundCamera? = null
    var joinedSSID: String? = null
    val supportsFocusMode: Boolean get() = false
    val supportsTapFocus: Boolean get() = can(CameraCapability.FOCUS)
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
    val faceAFArmed: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val wantsFaceDetect: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    private val _zoomReadout = MutableStateFlow(1.0)
    val zoomReadout: StateFlow<Double> = _zoomReadout.asStateFlow()
    val zoomDialReadout: StateFlow<Double> = _zoomReadout.asStateFlow()
    private val _zoomPinching = MutableStateFlow(false)
    val zoomPinching: StateFlow<Boolean> = _zoomPinching.asStateFlow()
    private val _trackingHud = MutableStateFlow(TrackingHud())
    val trackingHud: StateFlow<TrackingHud> = _trackingHud.asStateFlow()
    val isReconnecting: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    val isFeedRecovering: Boolean get() = recoveryState.value.isRecovering
    val isTrackingActive: Boolean get() = _trackingHud.value.isTracking
    val isFocusResetAvailable: Boolean get() = false

    init {
        scope.launch {
            backend.snapshot.collect { value ->
                _status.value = _status.value.copy(batteryPercent = value.batteryPercent ?: -1)
            }
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
                    ConnectionPhase.LIVE -> { holdsMonitor = true; _recoveryState.value = SessionRecoveryUi.Idle }
                    ConnectionPhase.FAILED ->
                        if (holdsMonitor) _recoveryState.value = SessionRecoveryUi.WaitingForOperator(1)
                    ConnectionPhase.IDLE -> { holdsMonitor = false; _recoveryState.value = SessionRecoveryUi.Idle }
                    else -> Unit
                }
            }
        }
        if (borrowing == null) {
            scope.launch(Dispatchers.Default) {
                backend.frames.collect { frame ->
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
            family = "generic", supportsTapFocus = CameraCapability.FOCUS in capabilities, supportsFocusMode = false,
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
    fun reconnect(id: String) { _connectionTargetId.value = id; backend.connect(id) }
    fun connect(camera: FoundCamera) {
        decoder.reset(); videoPackets = 0; hasVideoFormat = false
        _connectionTargetId.value = camera.id
        backend.connect(camera.id)
    }
    fun attachSurface(surface: Surface?) = decoder.attachSurface(surface)
    // Multiview needs a second DUML datalink; the Luna shell never offers it.
    fun updateMultiview(camera: FoundCamera?, driver: DatalinkDriver?, status: CameraStatus) = Unit
    fun adoptMultiviewPose(pose: GimbalStickMapping) = Unit
    fun receiveMultiview(frame: DumlFrame) = Unit
    fun releaseMultiview() = Unit
    override fun disconnect() {
        backend.disconnect(); decoder.reset()
        holdsMonitor = false; hasVideoFormat = false
        _connectionTargetId.value = null
        _trackingHud.value = TrackingHud()
    }
    fun close() { backend.close(); decoder.reset(); scope.cancel() }
    fun noteSceneBecameInactive() = backend.sceneActive(false)
    fun noteSceneBecameActive() = backend.sceneActive(true)
    internal fun hasRecoveryPicture(startedAt: Long): Boolean = hasVideoFormat
    fun retrySessionRecovery() { backend.connected.value?.let { backend.connect(it.id) } }
    fun abandonRecoveryToMenu() = disconnect()

    // Capture and exposure: not mapped on Android yet (iOS maps them through photography options).
    fun pressRecord() = unavailable("Recording from the app")
    fun pressShutter() = unavailable("The shutter")
    fun setEv(thirds: Int) = unavailable("Exposure compensation")
    fun setFacePriorityEnabled(on: Boolean) { if (on) unavailable("Face priority") }
    fun setIsoLimit(raw: Int) = unavailable("ISO limit")
    fun setApertureStrategy(raw: Int) = Unit
    fun getIsoLimit() = Unit
    suspend fun refreshIsoLimit(): Boolean = false
    fun setShootingMode(raw: Int) = unavailable("Shooting mode")

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
    fun performGimbalDoubleTap() = recenterGimbal()
    fun levelGimbalToWorld() = unavailable("World leveling")
    fun recenterGimbal() {
        if (!hasGimbal) return
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
    fun setGimbalMode(mode: GimbalMode) = unavailable("Gimbal mode")
    fun setGimbalSpeed(speed: GimbalSpeed) = unavailable("Gimbal speed")
    fun setGimbalWaypoint(slot: GimbalWaypointSlot) = unavailable("Programmed moves")
    fun clearGimbalWaypoint(slot: GimbalWaypointSlot) = Unit
    fun setGimbalLegDuration(ab: Double? = null, bc: Double? = null) = Unit
    fun setGimbalSmoothness(value: Double) = Unit
    fun setGimbalLoop(enabled: Boolean) = Unit
    fun clearGimbalProgram() = Unit
    fun runProgrammedMove() = unavailable("Programmed moves")
    fun pauseProgrammedMove() = Unit
    fun resumeProgrammedMove() = Unit
    fun restartProgrammedMove() = Unit
    fun cancelProgrammedMove() = Unit

    // Focus and Deep Track.
    fun handleFeedTap(x: Float, y: Float) = tapFocus(x, y)
    fun tapFocus(x: Float, y: Float) {
        if (!supportsTapFocus) return
        _focusPoint.value = x to y
        // The camera takes a top-left ROI; same 0.15 x 0.27 box as iOS.
        val left = (x - 0.075).coerceIn(0.0, 0.85)
        val top = (y - 0.135).coerceIn(0.0, 0.73)
        scope.launch { if (controls?.tapFocus(left, top) != true) presentControlNote("Focus did not reach the camera.") }
    }
    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) =
        startTracking(TrackingBox((x - width / 2).toDouble(), (y - height / 2).toDouble(), width.toDouble(), height.toDouble()))
    fun startTracking(box: TrackingBox) {
        if (!can(CameraCapability.TRACKING)) return unavailable("Deep Track")
        _trackingHud.value = TrackingHud(isTracking = true, draft = box)
        scope.launch {
            val left = box.x.coerceIn(0.0, 1.0)
            val top = box.y.coerceIn(0.0, 1.0)
            val ok = controls?.startTracking(left, top, minOf(box.width, 1 - left), minOf(box.height, 1 - top)) == true
            if (!ok) { _trackingHud.value = TrackingHud(); presentControlNote("Deep Track did not start.") }
        }
    }
    fun cancelSubjectTracking() = cancelTracking()
    fun cancelTracking() {
        if (!_trackingHud.value.isTracking) return
        _trackingHud.value = TrackingHud()
        scope.launch { controls?.stopTracking() }
    }
    fun handleGamepadAction(action: GamepadOperatorAction) = Unit
    fun handleGamepadTrackToggle() = if (isTrackingActive) cancelTracking() else startTracking(0.5f, 0.5f)
    fun resetFocusPoint() { _focusPoint.value = 0.5f to 0.5f }
    fun applyDetectedFaces(faces: List<TrackingBox>) = Unit
    fun considerFaceFrame(bitmap: android.graphics.Bitmap) = Unit
    fun noteLiveFrame() = Unit

    // Camera media is not mapped on Android yet.
    private var mediaOwner = 0L
    fun markBrowsingMedia(browsing: Boolean, resumePending: Boolean = false): Long {
        isBrowsingMedia = browsing
        return ++mediaOwner
    }
    fun ownsMediaLiveResume(owner: Long): Boolean = owner == mediaOwner
    suspend fun withMediaLiveResumeOwner(owner: Long, work: suspend () -> Unit) { if (ownsMediaLiveResume(owner)) work() }
    fun mediaLiveResumeExhausted(owner: Long) = Unit
    fun setOperatorOverlayHeld(held: Boolean) = Unit
    fun restartLiveViewAfterMedia(): Boolean = false
    fun beginMediaBrowse() { isBrowsingMedia = true }
    fun endMediaBrowse() { isBrowsingMedia = false }
    fun listMedia() = Unit
    fun deleteMedia(handle: Int) = unavailable("Camera media")
    fun setMediaFavorite(handle: Int, favorite: Boolean) = unavailable("Camera media")

    fun setIsoIndex(index: Int) = unavailable("ISO")
    fun setShutterDenom(denom: Int) = unavailable("Shutter")
    fun setExpoMode(mode: Int) = unavailable("Exposure mode")
    fun setWhiteBalanceAuto(tint: Int? = null) = unavailable("White balance")
    fun setWhiteBalance(kelvin: Int, tint: Int) = unavailable("White balance")
    fun setFocusMode(continuous: Boolean) = Unit
    fun setFocusTrack(mode: Int) = Unit
    fun refreshFocusTrack() = Unit
    fun setColorMode(mode: Int, hopEnabled: Boolean = false) = unavailable("Color profile")
    fun setVideoFormat(format: VideoFormat, fromOperator: Boolean = true): Boolean { unavailable("Format"); return false }
    fun setResolutionFps(res: Int, fpsIndex: Int): Boolean { unavailable("Format"); return false }
    // The Luna exposes no audio controls or level meters.
    fun setAudioChannel(value: Int) = Unit
    fun setVocalBoost(on: Boolean) = Unit
    fun setWindNr(on: Boolean) = Unit
    fun setDirectionalAudio(mode: Int) = Unit
    fun refreshAudio() = Unit

    companion object {
        /** Same chips as iOS `LunaShellMapping.zoomChips`; the ceiling is appended when larger. */
        val LUNA_ZOOM_CHIPS = listOf(1.0, 2.0, 4.0, 8.0, 15.0)
    }
}

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
    const val REBUILD_BACKOFF_MS = 60_000L
    const val COOLDOWN_MS = 15_000L
    const val REBUILD_COOLDOWN_MS = 5_000L
    const val ANALOG_LIFT_STALE_MS = 1_600L
    const val COMMAND_TIMEOUT_WINDOW_MS = 5_000L
    const val COMMAND_TIMEOUT_REBUILD_COUNT = 2
    const val FIRST_PICTURE_RESEND_MS = 2_000L
    const val FORMAT_POKE_MIN_SETTLE_MS = 800L
    const val STALLED_FORMAT_RESEND_MS = 5_000L
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

    fun shouldUseCapturedLiveStartForMediaResume(): Boolean = true

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

    /**
     * Mimo 20260828: HEVC at join+17 ms. Do not wait a DUML ACK before arming.
     */
    fun shouldWaitForLiveViewAckBeforeArm(): Boolean = false

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
                if (state.stage == Stage.FULL_REJOIN || state.stage == Stage.COOLDOWN) {
                    return Action.NONE
                }
                if (shouldHoldForGopReset(sinceEnable, videoAge)) return Action.NONE
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
            if (state.stage != Stage.IDLE && snap.now - state.lastActionAt < ESCALATE_MS) {
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

    /** Legacy gate used by tests: first-picture 2 s, stalled format 5 s — never 1 Hz. */
    fun shouldResendEnable(
        videoPackets: Int,
        nowElapsedRealtime: Long,
        lastIdrRequest: Long,
        hasFormat: Boolean,
        decoderErrors: Int,
        streamStartedAt: Long?,
    ): Boolean {
        if (videoPackets == 0) {
            return nowElapsedRealtime - lastIdrRequest >= FIRST_PICTURE_RESEND_MS
        }
        val started = streamStartedAt ?: nowElapsedRealtime
        val stalled =
            (decoderErrors > 0 && !hasFormat) ||
                (!hasFormat && nowElapsedRealtime - started > FORMAT_STALL_MS)
        if (!stalled) return false
        return nowElapsedRealtime - lastIdrRequest >= STALLED_FORMAT_RESEND_MS
    }
}
