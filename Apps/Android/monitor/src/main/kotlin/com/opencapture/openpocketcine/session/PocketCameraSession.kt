package com.opencapture.openpocketcine.session

import android.content.Context
import android.view.Surface
import com.opencapture.openpocketcine.GamepadOperatorAction
import com.opencapture.openpocketcine.MonitorConfiguration
import com.opencapture.openpocketcine.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/** Shared presentation session. Historical name is retained for source/JNI compatibility.
 * All camera transport lives behind CameraBackend; this class contains no camera writes.
 */
class PocketCameraSession(context: Context) : CameraSession {
    private val backend = MonitorConfiguration.createBackend(context.applicationContext)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val capabilities get() = backend.capabilities
    val decoder = HevcDecoder()
    override val phase get() = backend.phase.value
    val phaseFlow get() = backend.phase
    val failure get() = backend.failure
    val radioOn get() = backend.radioOn
    val found = backend.found.map { cameras -> cameras.map(::displayCamera) }.stateIn(scope, SharingStarted.Eagerly, emptyList())
    private val _status = MutableStateFlow(CameraStatus())
    val status = _status.asStateFlow()
    private val _controlNote = MutableStateFlow<String?>(null)
    val controlNote = _controlNote.asStateFlow()
    val controlBusy = MutableStateFlow(false).asStateFlow()
    val focusPoint = MutableStateFlow(0.5f to 0.5f).asStateFlow()
    val gimbalPoseViewFlip = MutableStateFlow(false).asStateFlow()
    val gimbalLimitPulse = MutableStateFlow(0).asStateFlow()
    val lastGimbalLimitContact = GimbalLimitContact()
    val lastGimbalLimitPanSign = 0.0
    val lastGimbalLimitTiltSign = 0.0
    var browsingMedia = false; private set
    val connectedCamera get() = backend.connected.value?.let(::displayCamera)
    val joinedSSID get() = backend.joinedSSID.value
    val supportsFocusMode get() = CameraCapability.FOCUS in capabilities
    val supportsTapFocus get() = CameraCapability.FOCUS in capabilities
    val supportsCameraControls get() = CameraCapability.CAMERA_SETTINGS in capabilities
    val supportsCameraMedia get() = CameraCapability.CAMERA_MEDIA in capabilities
    var videoPackets = 0; private set
    var accessUnits = 0; private set
    var framesEnqueued = 0; private set
    var droppedIncomplete = 0; private set
    var decoderErrors = 0; private set
    var hasVideoFormat = false; private set
    var nalTypes = ""; private set
    var lastKeyframeAge = "—"; private set
    var holdsMonitor = false; private set
    private val _recovery = MutableStateFlow<SessionRecoveryUi>(SessionRecoveryUi.Idle)
    val recoveryState = _recovery.asStateFlow()
    val isFormatPinActive = false
    val zoomColorHopPending = false
    val zoomPinchPreview: Double? = null
    val zoomOptimistic: Double? = null
    val faceAFArmed = MutableStateFlow(false).asStateFlow()
    val wantsFaceDetect = MutableStateFlow(false).asStateFlow()
    val zoomReadout = MutableStateFlow(1.0).asStateFlow()
    val zoomPinching = MutableStateFlow(false).asStateFlow()
    val trackingHud = MutableStateFlow(TrackingHud()).asStateFlow()
    val isReconnecting = MutableStateFlow(false).asStateFlow()
    val isFeedRecovering get() = recoveryState.value.isRecovering
    val isTrackingActive = false
    val isFocusResetAvailable = false

    init {
        scope.launch { backend.snapshot.collect { value -> _status.value = CameraStatus(firmware = value.firmware, batteryPercent = value.batteryPercent ?: -1) } }
        scope.launch { backend.phase.collect { value ->
            if (value == ConnectionPhase.LIVE) { holdsMonitor = true; _recovery.value = SessionRecoveryUi.Idle }
            if (value == ConnectionPhase.FAILED && holdsMonitor) _recovery.value = SessionRecoveryUi.WaitingForOperator(1)
            if (value == ConnectionPhase.IDLE) { holdsMonitor = false; _recovery.value = SessionRecoveryUi.Idle }
        } }
        scope.launch(Dispatchers.Default) { backend.frames.collect { frame ->
            videoPackets += 1; accessUnits += 1
            if (decoder.decode(frame.annexB)) { framesEnqueued += 1; hasVideoFormat = true }
            decoderErrors = decoder.decoderErrors.get()
        } }
    }
    private fun displayCamera(value: CameraIdentity) = FoundCamera(value.id, value.id, value.advertisedName, CameraModel(name = value.modelName, family = "generic", supportsTapFocus = supportsTapFocus, supportsFocusMode = supportsFocusMode, zoomStops = listOf(1.0), verified = true, tcpPoke = false, usesCapturedLiveEnable = false), null)
    override fun startScan() = backend.startScan()
    fun startScan(reconnect: String?) { if (reconnect == null) startScan() else backend.connect(reconnect) }
    fun reconnect(id: String) = backend.connect(id)
    fun connect(camera: FoundCamera) { decoder.reset(); videoPackets = 0; hasVideoFormat = false; backend.connect(camera.id) }
    fun attachSurface(surface: Surface?) = decoder.attachSurface(surface)
    override fun disconnect() { backend.disconnect(); decoder.reset(); holdsMonitor = false; hasVideoFormat = false }
    fun close() { backend.close(); decoder.reset(); scope.cancel() }
    fun noteSceneBecameInactive() = backend.sceneActive(false)
    fun noteSceneBecameActive() = backend.sceneActive(true)
    fun retrySessionRecovery() { backend.connected.value?.let { backend.connect(it.id) } }
    fun abandonRecoveryToMenu() = disconnect()
    fun clearControlNoteIf(note: String) { if (_controlNote.value == note) _controlNote.value = null }
    fun presentControlNote(note: String) { _controlNote.value = note }
    private fun unavailable() = presentControlNote("Camera controls are not connected yet. Live monitoring and view assists are ready.")
    fun pressRecord() = unavailable()
    fun pressShutter() = unavailable()
    fun setEv(thirds: Int) = unavailable()
    fun setFacePriorityEnabled(on: Boolean) { if (on) unavailable() }
    fun setIsoLimit(raw: Int) = unavailable()
    fun getIsoLimit() = Unit
    suspend fun refreshIsoLimit(): Boolean = false
    fun setShootingMode(raw: Int) = unavailable()
    fun zoomCycleFrom(): Double = 1.0
    fun zoomStops(): List<Double> = listOf(1.0)
    fun zoomMax(): Double = 1.0
    fun zoomNextJump(): Double = 1.0
    fun setZoomLens(position: Int) = unavailable()
    fun setZoom(factor: Double) = unavailable()
    fun setZoomSlider(factor: Double) = unavailable()
    fun setZoomSlew(value: Int) { if (value != 0) unavailable() }
    fun setZoomStop() = Unit
    fun updateZoomPinch(magnification: Double) = Unit
    fun endZoomPinch() = Unit
    fun recenterGimbal() = unavailable()
    fun flipGimbal() = unavailable()
    fun handleFeedTap(x: Float, y: Float) = Unit
    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) = unavailable()
    fun startTracking(box: TrackingBox) = unavailable()
    fun cancelSubjectTracking() = Unit
    fun cancelTracking() = Unit
    fun handleGamepadAction(action: GamepadOperatorAction) = unavailable()
    fun handleGamepadTrackToggle() = unavailable()
    fun resetFocusPoint() = Unit
    fun applyDetectedFaces(faces: List<TrackingBox>) = Unit
    fun considerFaceFrame(bitmap: android.graphics.Bitmap) = Unit
    fun noteLiveFrame() = decoder.notePresented()
    fun markBrowsingMedia(browsing: Boolean) { browsingMedia = browsing }
    fun setOperatorOverlayHeld(held: Boolean) = Unit
    fun restartLiveViewAfterMedia() = Unit
    fun beginMediaBrowse() { browsingMedia = true }
    fun endMediaBrowse() { browsingMedia = false }
    fun listMedia() = unavailable()
    fun deleteMedia(handle: Int) = unavailable()
    fun setMediaFavorite(handle: Int, favorite: Boolean) = unavailable()
    fun setIsoIndex(index: Int) = unavailable()
    fun setShutterDenom(denom: Int) = unavailable()
    fun setExpoMode(mode: Int) = unavailable()
    fun setWhiteBalanceAuto(tint: Int? = null) = unavailable()
    fun setWhiteBalance(kelvin: Int, tint: Int) = unavailable()
    fun setFocusMode(continuous: Boolean) = unavailable()
    fun setFocusTrack(mode: Int) = unavailable()
    fun refreshFocusTrack() = Unit
    fun setColorMode(mode: Int, hopEnabled: Boolean = false) = unavailable()
    fun setVideoFormat(format: VideoFormat): Boolean { unavailable(); return false }
    fun setResolutionFps(res: Int, fpsIndex: Int): Boolean { unavailable(); return false }
    fun setAudioChannel(value: Int) = unavailable()
    fun setVocalBoost(on: Boolean) = unavailable()
    fun setWindNr(on: Boolean) = unavailable()
    fun setDirectionalAudio(mode: Int) = unavailable()
    fun refreshAudio() = Unit
    fun updateGimbalStick(x: Float, y: Float, sensitivity: Int = 3, assistMirror: Boolean = false) = Unit
    fun endGimbalStick() = Unit
    fun tapFocus(x: Float, y: Float) = unavailable()
}
