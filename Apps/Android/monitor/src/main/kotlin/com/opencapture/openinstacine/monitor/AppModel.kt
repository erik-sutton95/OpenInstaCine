package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.MonitorLegalPage
import com.opencapture.opencine.appkit.MonitorOperatorSessionModel
import androidx.compose.runtime.Composable
import com.opencapture.opencine.appkit.MonitorCaptureField
import com.opencapture.opencine.appkit.MonitorCapturePreferences
import com.opencapture.opencine.appkit.captureField
import com.opencapture.opencine.appkit.readPhoneBatteryReadout
import com.opencapture.opencine.cameracontrols.CaptureRefresh
import com.opencapture.opencine.cameracontrols.CaptureSheetHost
import com.opencapture.opencine.cameracontrols.CaptureAudioService
import com.opencapture.opencine.cameracontrols.CaptureWheelState
import com.opencapture.opencine.cameracontrols.GamepadHost
import com.opencapture.opencine.cameracontrols.OperatorSetupModel
import com.opencapture.opencine.cameracontrols.GimbalChromeHost
import com.opencapture.opencine.cameracontrols.GimbalGamepadDriver
import com.opencapture.opencine.cameracontrols.LiveGimbalPanel
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.motion.GimbalWaypointSlot
import com.opencapture.opencine.runtime.MonitorHDRDisplay
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureSetting
import com.opencapture.opencine.vocabulary.GamepadOperatorAction
import com.opencapture.opencine.vocabulary.GimbalDoubleTap
import com.opencapture.opencine.vocabulary.GimbalMode
import com.opencapture.opencine.vocabulary.GimbalRamp
import com.opencapture.opencine.vocabulary.GimbalSpeed
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.appkit.AppIntegration
import com.opencapture.opencine.appkit.BodyRecordsV0
import com.opencapture.opencine.appkit.CamerasModel
import com.opencapture.opencine.appkit.IntegrationSlots
import com.opencapture.opencine.appkit.NearbyCardCopy
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.appkit.SavedCamerasStore
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.StoredString
import com.opencapture.opencine.appkit.stored
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.insta360.luna.LunaFailures
import com.opencapture.opencine.insta360.luna.LunaIntegration
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.openinstacine.monitor.assists.createLiveAssistState
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import com.opencapture.openinstacine.monitor.session.SHELL_WAYPOINT_WIDE_HFOV_DEG
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import com.opencapture.monitorui.settings.MonitorSettingsTab
import com.opencapture.opencine.cameracontrols.PortraitFeedAspect

class AppModel(
    context: Context,
) : GamepadHost, GimbalChromeHost, CaptureSheetHost, OperatorSetupModel, AutoCloseable {
    private val appContext = context.applicationContext
    init {
        DiagnosticCenter.install(appContext)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val session = PocketCameraSession(context)
    private val mediaStorage = com.opencapture.opencine.appkit.MonitorMediaCacheStorage()
    private val initialMedia = com.opencapture.openinstacine.monitor.media.createLunaMediaLibrary(appContext, session, mediaStorage, null, scope)
    var mediaLibrary by mutableStateOf(initialMedia.first)
        private set
    var mediaPlayback by mutableStateOf(initialMedia.second)
        private set
    private var mediaServiceID: com.opencapture.opencine.core.CameraSessionID? = null
    val scopeBus = com.opencapture.opencine.runtime.ScopeSampleBus()
    val inspectorPreview = com.opencapture.opencine.runtime.InspectorPreviewPipeline(scopeBus,
        { com.opencapture.opencine.runtime.NativeGlBackend.create(it) }, logTag = "OpcInspector")
    override val assist = createLiveAssistState(appContext)

    /**
     * Cameras and pairing through the shared OpenCine flow (SHELL-02): the Luna integration over
     * the session's port, with its nearby cards in this app's words. No integration for a backend that
     * is not a Luna port (the debug local replay starts itself on the first scan).
     */
    override val cameras = CamerasModel(
        listOfNotNull(
            session.lunaPort?.let { AppIntegration(LunaIntegration(it), IntegrationSlots(nearbyCard = Companion::nearbyCard)) },
        ),
        camerasStore(
            appContext.getSharedPreferences("openpocketcine.cameras", Context.MODE_PRIVATE).stored("document"),
            appContext.getSharedPreferences(LEGACY_CAMERAS, Context.MODE_PRIVATE).stored("records-json"),
        ),
        scope,
    )

    /**
     * The root over [cameras] (SHELL-03): cameras, pair or the monitor, its cover (Settings or
     * Media), the monitor camera's session lifetime and the shared common controls.
     */
    val shell = ShellModel(cameras, session.control).also { shell ->
        shell.onSceneActivity = { active -> if (active) session.noteSceneBecameActive() else session.noteSceneBecameInactive() }
    }

    val savedCameras: List<SavedCamera> get() = cameras.state.value.saved
    /** Long-press on the tap-focus box locks it: feed taps no longer move focus. */
    var focusBoxLocked by mutableStateOf(false)
    var coreVersion by mutableStateOf<String?>(null)
    /** A legal document over the cameras page (product composition, not a shell cover). */
    var legal by mutableStateOf<MonitorLegalPage?>(null)
    internal val operatorSession = MonitorOperatorSessionModel(shell, assist, OperatorPrefs.displayPreferences(appContext), scope)
    override var operatorSettingsTab: MonitorSettingsTab
        get() = operatorSession.settingsTab
        set(value) { operatorSession.settingsTab = value }
    var chromeEditorMode: PocketDispMode?
        get() = operatorSession.editingMode
        set(value) { operatorSession.editingMode = value }
    override var chromeEditorReturnMode: PocketDispMode?
        get() = operatorSession.returnedMode
        set(value) { operatorSession.returnedMode = value }
    override val liveChromeInteractive: Boolean get() = operatorSession.interactive
    override var keepScreenAwake by mutableStateOf(OperatorPrefs.keepScreenAwake(appContext))
        private set
    override var hdrDisplay by mutableStateOf(OperatorPrefs.hdrDisplay(appContext))
        private set
    var screenCaptured by mutableStateOf(false)
    val hdrDisplayActive: Boolean
        get() = MonitorHDRDisplay.isEffective(hdrDisplay, screenCaptured)
    override var cacheFullResolution by mutableStateOf(OperatorPrefs.cacheFullResolution(appContext))
        private set
    override var recordConfirmationEnabled by mutableStateOf(OperatorPrefs.recordConfirmationEnabled(appContext))
        private set
    override var hapticsEnabled by mutableStateOf(OperatorPrefs.hapticsEnabled(appContext))
        private set
    override var gimbalStickSensitivity by mutableIntStateOf(OperatorPrefs.gimbalStickSensitivity(appContext))
        private set
    override var virtualJoystickInvertPan by mutableStateOf(OperatorPrefs.virtualJoystickInvertPan(appContext))
        private set
    override var virtualJoystickInvertTilt by mutableStateOf(OperatorPrefs.virtualJoystickInvertTilt(appContext))
        private set
    override var virtualJoystickDeadzonePercent by mutableIntStateOf(
        OperatorPrefs.virtualJoystickDeadzonePercent(appContext),
    )
        private set
    override var virtualJoystickResponseCurve by mutableStateOf(
        OperatorPrefs.virtualJoystickResponseCurve(appContext),
    )
        private set
    override var virtualJoystickSize by mutableStateOf(OperatorPrefs.virtualJoystickSize(appContext))
        private set
    val virtualJoystickMapping: CameraCommands.VirtualJoystickMapping
        get() =
            CameraCommands.VirtualJoystickMapping(
                invertPan = virtualJoystickInvertPan,
                invertTilt = virtualJoystickInvertTilt,
                deadzone = CameraCommands.VirtualJoystickMapping.deadzoneFromPercent(
                    virtualJoystickDeadzonePercent,
                ),
                curve = virtualJoystickResponseCurve,
            )
    override var gimbalRamp by mutableStateOf(OperatorPrefs.gimbalRamp(appContext))
        private set
    override var gimbalDoubleTap by mutableStateOf(OperatorPrefs.gimbalDoubleTap(appContext))
        private set
    override var liveGimbalPanel by mutableStateOf(LiveGimbalPanel.NONE)
    /** Canvas-space centre of the programmed-move editor / Run pill. Null until first open or drag. */
    override var gimbalFloatCenter by mutableStateOf<Offset?>(null)
    var gimbalDebugCenter by mutableStateOf<Offset?>(null)

    init {
        session.gimbalRamp = gimbalRamp
        session.gimbalDoubleTap = gimbalDoubleTap
    }
    val dispLive: PocketDispChrome get() = operatorSession.live
    val dispClean: PocketDispChrome get() = operatorSession.clean
    var cleanViewPinnedTools by mutableStateOf(OperatorPrefs.cleanViewPinnedTools(appContext))
        private set
    var portraitFeedAspect by mutableStateOf(OperatorPrefs.portraitFeedAspect(appContext))
        private set
    var nativeISOHopEnabled by mutableStateOf(OperatorPrefs.nativeISOHopEnabled(appContext))
        private set
    var facePriorityExposureEnabled by mutableStateOf(OperatorPrefs.facePriorityExposureEnabled(appContext))
        private set
    var shutterUsesAngle by mutableStateOf(OperatorPrefs.shutterUsesAngle(appContext))
        private set
    override var lutSelection by mutableStateOf(OperatorPrefs.lutSelection(appContext))
        private set
    var assistClean: Boolean
        get() = assist.clean
        set(value) { assist.clean = value }
    var phoneBatteryPercent by mutableIntStateOf(-1)
        private set
    var phoneCharging by mutableStateOf(false)
        private set
    var uiLocked by mutableStateOf(false)
    override val gimbalGamepad = GimbalGamepadDriver(OperatorPrefs::gimbalGamepadStick)
    override var gamepadConnected by mutableStateOf(false)

    val currentDispMode: PocketDispMode get() = operatorSession.mode
    val dispChrome: PocketDispChrome get() = operatorSession.chrome
    override val isEditingChrome: Boolean get() = operatorSession.isEditing
    override fun chrome(mode: PocketDispMode): PocketDispChrome = operatorSession.chrome(mode)
    fun chromeSectionMounts(section: PocketDispSection): Boolean = operatorSession.mounts(section)
    override fun toggleChrome(section: PocketDispSection, mode: PocketDispMode) = operatorSession.toggle(section, mode)

    override fun beginChromeEditing(mode: PocketDispMode) {
        liveGimbalPanel = LiveGimbalPanel.NONE
        operatorSession.beginEditing(mode)
    }

    fun endChromeEditing() = operatorSession.finishEditing()
    fun setDisplayMode(clean: Boolean) { assist.clean = clean }

    fun noteBecameLive() {
        operatorSession.synchronize(shell.state.value.monitor?.id)
    }

    override fun updateKeepScreenAwake(value: Boolean) {
        keepScreenAwake = value
        OperatorPrefs.setKeepScreenAwake(appContext, value)
    }

    override fun updateHdrDisplay(value: Boolean) {
        hdrDisplay = value
        OperatorPrefs.setHdrDisplay(appContext, value)
    }

    override fun updateCacheFullResolution(value: Boolean) {
        cacheFullResolution = value
        OperatorPrefs.setCacheFullResolution(appContext, value)
    }

    override fun updateRecordConfirmationEnabled(value: Boolean) {
        recordConfirmationEnabled = value
        OperatorPrefs.setRecordConfirmationEnabled(appContext, value)
    }

    override fun updateHapticsEnabled(value: Boolean) {
        hapticsEnabled = value
        OperatorPrefs.setHapticsEnabled(appContext, value)
    }

    override fun updateGimbalDoubleTap(value: GimbalDoubleTap) {
        gimbalDoubleTap = value
        OperatorPrefs.setGimbalDoubleTap(appContext, value)
        session.gimbalDoubleTap = value
    }

    override fun updateGimbalRamp(value: GimbalRamp) {
        gimbalRamp = value
        OperatorPrefs.setGimbalRamp(appContext, value)
        session.gimbalRamp = value
    }

    override fun updateGimbalStickSensitivity(value: Int) {
        val clamped = value.coerceIn(1, 5)
        gimbalStickSensitivity = clamped
        OperatorPrefs.setGimbalStickSensitivity(appContext, clamped)
    }

    override fun updateVirtualJoystickInvertPan(value: Boolean) {
        virtualJoystickInvertPan = value
        OperatorPrefs.setVirtualJoystickInvertPan(appContext, value)
    }

    override fun updateVirtualJoystickInvertTilt(value: Boolean) {
        virtualJoystickInvertTilt = value
        OperatorPrefs.setVirtualJoystickInvertTilt(appContext, value)
    }

    override fun updateVirtualJoystickDeadzonePercent(value: Int) {
        val clamped = CameraCommands.VirtualJoystickMapping.clampedDeadzonePercent(value)
        virtualJoystickDeadzonePercent = clamped
        OperatorPrefs.setVirtualJoystickDeadzonePercent(appContext, clamped)
    }

    override fun updateVirtualJoystickResponseCurve(value: CameraCommands.VirtualJoystickCurve) {
        virtualJoystickResponseCurve = value
        OperatorPrefs.setVirtualJoystickResponseCurve(appContext, value)
    }

    override fun updateVirtualJoystickSize(value: com.opencapture.monitorui.MonitorJoystickSize) {
        virtualJoystickSize = value
        OperatorPrefs.setVirtualJoystickSize(appContext, value)
    }

    fun updatePortraitFeedAspect(value: PortraitFeedAspect) {
        portraitFeedAspect = value
        OperatorPrefs.setPortraitFeedAspect(appContext, value)
    }

    fun updateNativeISOHopEnabled(value: Boolean) {
        nativeISOHopEnabled = value
        OperatorPrefs.setNativeISOHopEnabled(appContext, value)
    }

    fun updateFacePriorityExposureEnabled(value: Boolean) {
        facePriorityExposureEnabled = value
        OperatorPrefs.setFacePriorityExposureEnabled(appContext, value)
        session.setFacePriorityEnabled(value)
    }

    fun updateShutterUsesAngle(value: Boolean) {
        shutterUsesAngle = value
        OperatorPrefs.setShutterUsesAngle(appContext, value)
    }

    fun updateLutSelection(value: String) {
        lutSelection = value
        OperatorPrefs.setLutSelection(appContext, value)
    }

    override fun updateCleanViewPinnedTools(value: Set<String>) {
        cleanViewPinnedTools = value
        OperatorPrefs.setCleanViewPinnedTools(appContext, value)
    }

    fun toggleUiLocked() {
        uiLocked = !uiLocked
    }

    fun refreshPhoneBattery() {
        val readout =
            readPhoneBatteryReadout(
                appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)),
                appContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager,
            )
        applyPhoneBattery(readout.percent ?: -1, readout.externalPower == true)
    }

    fun applyPhoneBattery(percent: Int, charging: Boolean) {
        phoneBatteryPercent = percent
        phoneCharging = charging
    }

    fun pressRecord() = session.pressRecord()

    fun pressShutter() = session.pressShutter()

    fun setEv(thirds: Int) = session.setEv(thirds)

    fun setIsoLimit(raw: Int) = session.setIsoLimit(raw)

    fun setApertureStrategy(raw: Int) = session.setApertureStrategy(raw)

    fun refreshIsoLimit() = session.getIsoLimit()

    suspend fun refreshIsoLimitNow(): Boolean = session.refreshIsoLimit()

    fun setShootingMode(raw: Int) = session.setShootingMode(raw)

    fun setZoom(factor: Double) = session.setZoom(factor)

    fun setZoomLens(position: Int) = session.setZoomLens(position)

    fun setZoomSlew(value: Int) = session.setZoomSlew(value)

    fun setZoomStop() = session.setZoomStop()

    fun recenterGimbal() = session.recenterGimbal()

    fun flipGimbal() = session.flipGimbal()

    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) =
        session.startTracking(x, y, width, height)

    fun cancelTracking() = session.cancelTracking()

    fun resetFocusPoint() {
        focusBoxLocked = false
        session.resetFocusPoint()
    }

    fun beginMediaBrowse() = session.beginMediaBrowse()

    fun endMediaBrowse() = session.endMediaBrowse()

    fun setIsoIndex(index: Int) = session.setIsoIndex(index)

    fun setShutterDenom(denom: Int) = session.setShutterDenom(denom)

    fun setExpoMode(mode: Int) = session.setExpoMode(mode)

    fun setWhiteBalanceAuto(tint: Int? = null) = session.setWhiteBalanceAuto(tint)

    fun setWhiteBalance(kelvin: Int, tint: Int) = session.setWhiteBalance(kelvin, tint)

    fun setFocusMode(continuous: Boolean) = session.setFocusMode(continuous)

    fun setFocusTrack(mode: Int) = session.setFocusTrack(mode)

    fun refreshFocusTrack() = session.refreshFocusTrack()

    fun setColorMode(mode: Int) = session.setColorMode(mode, nativeISOHopEnabled)

    fun setResolutionFps(res: Int, fpsIndex: Int) {
        val format = VideoFormat.parse(res, fpsIndex) ?: return
        setVideoFormat(format)
    }

    fun setVideoFormat(format: VideoFormat) {
        session.setVideoFormat(format)
    }






    fun tapFocus(x: Float, y: Float) = session.tapFocus(x, y)

    fun updateGimbalStick(x: Float, y: Float) {
        if (uiLocked) return
        session.updateGimbalStick(
            x,
            y,
            gimbalStickSensitivity,
            assist.mirrorsHorizontally,
            mapping = virtualJoystickMapping,
        )
    }

    override fun updateGimbalPadStick(x: Float, y: Float) {
        if (uiLocked) return
        session.updateGimbalStick(x, y, gimbalStickSensitivity, assist.mirrorsHorizontally)
    }

    override fun endGimbalStick() = session.endGimbalStick()

    val isLive: Boolean
        get() = shell.state.value.monitor != null

    internal val operatorCaptureSource by lazy { makeOperatorCaptureSource() }

    // CaptureSheetHost (camera-controls): the capture sheets read these values and commit through one typed entry.
    override val camera get() = session.connectedCamera?.model
    override val audioService: CaptureAudioService? get() = null
    override fun captureField(sheet: LiveSheet, expoMode: Int): MonitorCaptureField? =
        captureSettingKey(sheet)?.let { session.control.captureField(it) }
    @Composable override fun captureSessionState(status: CameraStatus) = observedCaptureSessionState(status)
    override val capturePreferences get() = MonitorCapturePreferences(nativeISOHopEnabled,
        facePriorityExposureEnabled, shutterUsesAngle, OperatorPrefs.shutterAngleDegrees(appContext))
    override fun updateCapturePreferences(value: MonitorCapturePreferences) {
        if (value.nativeIsoHop != nativeISOHopEnabled) updateNativeISOHopEnabled(value.nativeIsoHop)
        if (value.facePriorityExposure != facePriorityExposureEnabled) updateFacePriorityExposureEnabled(value.facePriorityExposure)
        if (value.shutterUsesAngle != shutterUsesAngle) updateShutterUsesAngle(value.shutterUsesAngle)
    }
    override fun commit(setting: CaptureSetting, field: MonitorCaptureField?, status: CameraStatus) =
        routeCaptureSetting(setting, field, status)
    override suspend fun refresh(what: CaptureRefresh) = refreshForCaptureSheet(what)
    @Composable override fun CommonDrum(sheet: LiveSheet, status: CameraStatus, field: MonitorCaptureField?,
        enabled: Boolean, wheel: CaptureWheelState) = InstaCommonDrum(sheet, status, field, enabled, wheel)

    // GimbalChromeHost (camera-controls): the gimbal chrome reads these host values and reaches the session through the rest.
    override val mirrorsHorizontally get() = assist.mirrorsHorizontally
    override val labelProfile get() = session.profile.labels
    override val waypointWideHFovDeg get() = SHELL_WAYPOINT_WIDE_HFOV_DEG
    override val connectedCameraId get() = session.connectedCamera?.id
    override val phase get() = session.phase
    override val phaseFlow get() = session.phaseFlow
    override val gimbalMode get() = session.gimbalMode
    override val gimbalSpeed get() = session.gimbalSpeed
    override val gimbalProgram get() = session.gimbalProgram
    override val gimbalMoveRunning get() = session.gimbalMoveRunning
    override val gimbalMovePaused get() = session.gimbalMovePaused
    override val gimbalMoveCountdown get() = session.gimbalMoveCountdown
    override val gimbalPoseInvertPan get() = session.gimbalPoseInvertPan
    override val chromeStatus get() = session.chromeStatus
    override val canRunProgrammedMove get() = session.canRunProgrammedMove
    override fun predictedGimbalWaypoint(nowSeconds: Double) = session.predictedGimbalWaypoint(nowSeconds)
    override fun programmedZoomUnavailableReason(status: CameraStatus) = session.programmedZoomUnavailableReason(status)
    override fun setGimbalMode(mode: GimbalMode) = session.setGimbalMode(mode)
    override fun setGimbalSpeed(speed: GimbalSpeed) = session.setGimbalSpeed(speed)
    override fun setGimbalWaypoint(slot: GimbalWaypointSlot) = session.setGimbalWaypoint(slot)
    override fun clearGimbalWaypoint(slot: GimbalWaypointSlot) = session.clearGimbalWaypoint(slot)
    override fun setGimbalLegDuration(ab: Double?, bc: Double?) = session.setGimbalLegDuration(ab, bc)
    override fun setGimbalSmoothness(value: Double) = session.setGimbalSmoothness(value)
    override fun setGimbalLoop(enabled: Boolean) = session.setGimbalLoop(enabled)
    override fun clearGimbalProgram() = session.clearGimbalProgram()
    override fun runProgrammedMove() = session.runProgrammedMove()
    override fun restartProgrammedMove() = session.restartProgrammedMove()
    override fun pauseProgrammedMove() = session.pauseProgrammedMove()
    override fun resumeProgrammedMove() = session.resumeProgrammedMove()
    override fun cancelProgrammedMove() = session.cancelProgrammedMove()

    // GamepadHost (camera-controls): the gamepad driver reaches the session through these.
    override val lastGimbalLimitContact get() = session.lastGimbalLimitContact
    override val zoomReadout get() = session.zoomReadout.value
    override val zoomColorHopPending get() = session.zoomColorHopPending
    override fun presentControlNote(note: String) = session.presentControlNote(note)
    override fun zoomMax() = session.zoomMax()
    override fun updateZoomPinch(magnification: Double) = session.updateZoomPinch(magnification)
    override fun endZoomPinch() = session.endZoomPinch()
    override fun handleGamepadAction(action: GamepadOperatorAction) = session.handleGamepadAction(action)

    override fun canDriveGimbalPad(): Boolean =
        isLive &&
            !uiLocked &&
            shell.state.value.cover == null &&
            !isEditingChrome &&
            !session.browsingMedia

    fun prepareStartup() {
        coreVersion =
            if (SwiftCore.isAvailable) runCatching { SwiftCore.coreVersion() }.getOrNull() else null
        scope.launch {
            shell.state.map { it.monitor?.id }.distinctUntilChanged().collect {
                val connected = shell.state.value.monitor?.camera
                val service = connected?.services?.get<com.opencapture.opencine.media.CameraMediaService>()
                val key = session.connectedCamera?.id?.takeIf { it.isNotEmpty() }
                    ?: appContext.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE).getString("opc.media.lastCameraID", null) ?: "unknown"
                if (key != mediaPlayback.cameraId) {
                    val retired = mediaLibrary; retired.close()
                    val next = com.opencapture.openinstacine.monitor.media.createLunaMediaLibrary(appContext, session, mediaStorage, service, scope)
                    mediaLibrary = next.first; mediaPlayback = next.second
                    scope.launch { retired.dispose() }
                } else if (mediaServiceID != service?.sessionID) mediaLibrary.bind(service)
                mediaServiceID = service?.sessionID
                if (connected != null) noteBecameLive() else operatorSession.close()
            }
        }
        scope.launch {
            shell.state.map { it.cover }.distinctUntilChanged().collect { cover ->
                if (cover != ShellModel.Cover.MEDIA) { mediaLibrary.close(); session.endMediaBrowse() }
            }
        }
        scope.launch { session.mediaCaptured.collect {
            if (mediaLibrary.state.value.browsing && !mediaLibrary.state.value.fetching) mediaLibrary.refresh()
        } }
        // The link ended (idle, or failed without recovery holding the picture): back to the cameras
        // page, as the old live switch did. Recovery while live stays the session's.
        scope.launch {
            session.phaseFlow.collect { phase ->
                val ended = phase == ConnectionPhase.IDLE || (phase == ConnectionPhase.FAILED && !session.holdsMonitor)
                if (ended && shell.state.value.monitor != null) shell.close()
            }
        }
    }

    override fun disconnect() {
        focusBoxLocked = false
        shell.close()
        session.disconnect()
    }

    override fun close() {
        mediaLibrary.close()
        inspectorPreview.close()
        gimbalGamepad.stopListening()
        scope.cancel()
        // The activity ends: its camera session ends with it, without restarting discovery.
        shell.state.value.monitor?.session?.closeNow(SessionCloseReason.REQUESTED)
        session.close()
    }

    companion object {
        /** The records every earlier build reads, kept mirrored (SHELL-02 D11). */
        const val LEGACY_CAMERAS = "openpocketcine.saved-cameras"

        /** The saved-camera document over the legacy records, as this app stores them. */
        fun camerasStore(document: StoredString, legacy: StoredString) = SavedCamerasStore(
            document,
            SavedCamerasStore.Legacy(legacy, BodyRecordsV0(LunaFailures.INTEGRATION, BodyRecordsV0.Dates.EPOCH_MILLISECONDS), LEGACY_CAMERAS),
        )

        /** A nearby Luna in this app's words (the iPhone app's subtitle, the status it has always shown). */
        fun nearbyCard(camera: NearbyCamera) = NearbyCardCopy(camera.name, "Insta360 · nearby", "Needs approval on the camera")
    }
}
