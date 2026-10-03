package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.appkit.AppIntegration
import com.opencapture.opencine.appkit.BodyRecordsV0
import com.opencapture.opencine.appkit.CamerasModel
import com.opencapture.opencine.appkit.IntegrationSlots
import com.opencapture.opencine.appkit.SavedCamerasStore
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.StoredString
import com.opencapture.opencine.appkit.stored
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.insta360.luna.LunaFailures
import com.opencapture.opencine.insta360.luna.LunaIntegration
import com.opencapture.openpocketcine.pairing.LocalPairingCallouts
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.createLiveAssistState
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.GimbalDoubleTap
import com.opencapture.openpocketcine.session.GimbalRamp
import com.opencapture.openpocketcine.session.PocketCameraSession
import com.opencapture.openpocketcine.session.VideoFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** [borrowing] builds a Live View model over a Multiview tile's decoder (iOS `CameraSession(borrowing:)`). */
class AppModel(
    context: Context,
    borrowing: com.opencapture.opencine.decoder.HevcDecoder? = null,
    controlLease: com.opencapture.openpocketcine.session.MultiviewControlLease? = null,
) {
    private val appContext = context.applicationContext
    init {
        DiagnosticCenter.install(appContext)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val session = PocketCameraSession(context, borrowing, controlLease)
    private val mediaStorage = com.opencapture.opencine.appkit.MonitorMediaCacheStorage()
    private val initialMedia = com.opencapture.openpocketcine.media.createLunaMediaLibrary(appContext, session, mediaStorage, null, scope)
    var mediaLibrary by mutableStateOf(initialMedia.first)
        private set
    var mediaPlayback by mutableStateOf(initialMedia.second)
        private set
    private var mediaServiceID: com.opencapture.opencine.core.CameraSessionID? = null
    val scopeBus = com.opencapture.opencine.runtime.ScopeSampleBus()
    val inspectorPreview = com.opencapture.opencine.runtime.InspectorPreviewPipeline(scopeBus,
        { com.opencapture.openpocketcine.feed.Media3GlBackend(it) }, logTag = "OpcInspector")
    val assist = createLiveAssistState(appContext)

    /**
     * Cameras and pairing through the shared OpenCine flow (SHELL-02): the Luna integration over
     * the session's port, its pairing callouts from the activity. No integration for a backend that
     * is not a Luna port (the debug local replay starts itself on the first scan).
     */
    val cameras = CamerasModel(
        listOfNotNull(
            session.lunaPort?.let { AppIntegration(LunaIntegration(it), IntegrationSlots(pairing = { LocalPairingCallouts.current() })) },
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
    var showsLaunchSplash by mutableStateOf(true)
    /** Long-press on the tap-focus box locks it: feed taps no longer move focus. */
    var focusBoxLocked by mutableStateOf(false)
    var coreVersion by mutableStateOf<String?>(null)
    /** A legal document over the cameras page (product composition, not a shell cover). */
    var legal by mutableStateOf<LegalKind?>(null)
    var operatorSettingsTab by mutableStateOf(OperatorSettingsTab.LINK)
    var chromeEditorMode by mutableStateOf<PocketDispMode?>(null)
    var chromeEditorReturnMode by mutableStateOf<PocketDispMode?>(null)
    var liveChromeInteractive by mutableStateOf(true)
    var keepScreenAwake by mutableStateOf(OperatorPrefs.keepScreenAwake(appContext))
        private set
    var hdrDisplay by mutableStateOf(OperatorPrefs.hdrDisplay(appContext))
        private set
    var screenCaptured by mutableStateOf(false)
    val hdrDisplayActive: Boolean
        get() = HdrDisplay.isEffective(hdrDisplay, screenCaptured)
    var cacheFullResolution by mutableStateOf(OperatorPrefs.cacheFullResolution(appContext))
        private set
    var recordConfirmationEnabled by mutableStateOf(OperatorPrefs.recordConfirmationEnabled(appContext))
        private set
    var hapticsEnabled by mutableStateOf(OperatorPrefs.hapticsEnabled(appContext))
        private set
    var gimbalStickSensitivity by mutableIntStateOf(OperatorPrefs.gimbalStickSensitivity(appContext))
        private set
    var virtualJoystickInvertPan by mutableStateOf(OperatorPrefs.virtualJoystickInvertPan(appContext))
        private set
    var virtualJoystickInvertTilt by mutableStateOf(OperatorPrefs.virtualJoystickInvertTilt(appContext))
        private set
    var virtualJoystickDeadzonePercent by mutableIntStateOf(
        OperatorPrefs.virtualJoystickDeadzonePercent(appContext),
    )
        private set
    var virtualJoystickResponseCurve by mutableStateOf(
        OperatorPrefs.virtualJoystickResponseCurve(appContext),
    )
        private set
    var virtualJoystickSize by mutableStateOf(OperatorPrefs.virtualJoystickSize(appContext))
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
    var gimbalRamp by mutableStateOf(OperatorPrefs.gimbalRamp(appContext))
        private set
    var gimbalDoubleTap by mutableStateOf(OperatorPrefs.gimbalDoubleTap(appContext))
        private set
    var liveGimbalPanel by mutableStateOf(LiveGimbalPanel.NONE)
    /** Canvas-space centre of the programmed-move editor / Run pill. Null until first open or drag. */
    var gimbalFloatCenter by mutableStateOf<Offset?>(null)
    var gimbalDebugCenter by mutableStateOf<Offset?>(null)

    init {
        session.gimbalRamp = gimbalRamp
        session.gimbalDoubleTap = gimbalDoubleTap
    }
    var dispLive by mutableStateOf(OperatorPrefs.dispLive(appContext))
        private set
    var dispClean by mutableStateOf(OperatorPrefs.dispClean(appContext))
        private set
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
    var lutSelection by mutableStateOf(OperatorPrefs.lutSelection(appContext))
        private set
    var assistClean by mutableStateOf(false)
    var phoneBatteryPercent by mutableIntStateOf(-1)
        private set
    var phoneCharging by mutableStateOf(false)
        private set
    var uiLocked by mutableStateOf(false)
    val gimbalGamepad = GimbalGamepadDriver()
    var gamepadConnected by mutableStateOf(false)

    val currentDispMode: PocketDispMode
        get() = if (assistClean) PocketDispMode.CLEAN else PocketDispMode.LIVE

    val dispChrome: PocketDispChrome
        get() = chrome(currentDispMode)

    val isEditingChrome: Boolean
        get() = chromeEditorMode != null

    fun chrome(mode: PocketDispMode): PocketDispChrome =
        when (mode) {
            PocketDispMode.LIVE -> dispLive
            PocketDispMode.CLEAN -> dispClean
        }

    fun chromeSectionMounts(section: PocketDispSection): Boolean {
        val editing = chromeEditorMode
        if (editing != null && editing == currentDispMode) return true
        if (section == PocketDispSection.RAIL_SETTINGS && !dispLive.railSettings && !dispClean.railSettings) {
            return true
        }
        return dispChrome.isVisible(section)
    }

    fun toggleChrome(section: PocketDispSection, mode: PocketDispMode) {
        when (mode) {
            PocketDispMode.LIVE -> {
                dispLive = dispLive.toggling(section)
                OperatorPrefs.setDispLive(appContext, dispLive)
            }
            PocketDispMode.CLEAN -> {
                dispClean = dispClean.toggling(section)
                OperatorPrefs.setDispClean(appContext, dispClean)
            }
        }
    }

    fun beginChromeEditing(mode: PocketDispMode) {
        shell.dismissCover()
        liveGimbalPanel = LiveGimbalPanel.NONE
        setDisplayMode(clean = mode == PocketDispMode.CLEAN)
        chromeEditorMode = mode
    }

    fun endChromeEditing() {
        chromeEditorReturnMode = chromeEditorMode
        chromeEditorMode = null
        operatorSettingsTab = OperatorSettingsTab.DISPLAY
        shell.open(ShellModel.Cover.SETTINGS)
    }

    fun setDisplayMode(clean: Boolean) {
        assistClean = clean
    }

    /** A new monitor: no leftover Edit view, and the connect tap cannot hit live chrome. */
    fun noteBecameLive() {
        chromeEditorMode = null
        liveChromeInteractive = false
        scope.launch {
            kotlinx.coroutines.delay(550)
            liveChromeInteractive = true
        }
    }

    fun updateKeepScreenAwake(value: Boolean) {
        keepScreenAwake = value
        OperatorPrefs.setKeepScreenAwake(appContext, value)
    }

    fun updateHdrDisplay(value: Boolean) {
        hdrDisplay = value
        OperatorPrefs.setHdrDisplay(appContext, value)
    }

    fun updateCacheFullResolution(value: Boolean) {
        cacheFullResolution = value
        OperatorPrefs.setCacheFullResolution(appContext, value)
    }

    fun updateRecordConfirmationEnabled(value: Boolean) {
        recordConfirmationEnabled = value
        OperatorPrefs.setRecordConfirmationEnabled(appContext, value)
    }

    fun updateHapticsEnabled(value: Boolean) {
        hapticsEnabled = value
        OperatorPrefs.setHapticsEnabled(appContext, value)
    }

    fun updateGimbalDoubleTap(value: GimbalDoubleTap) {
        gimbalDoubleTap = value
        OperatorPrefs.setGimbalDoubleTap(appContext, value)
        session.gimbalDoubleTap = value
    }

    fun updateGimbalRamp(value: GimbalRamp) {
        gimbalRamp = value
        OperatorPrefs.setGimbalRamp(appContext, value)
        session.gimbalRamp = value
    }

    fun updateGimbalStickSensitivity(value: Int) {
        val clamped = value.coerceIn(1, 5)
        gimbalStickSensitivity = clamped
        OperatorPrefs.setGimbalStickSensitivity(appContext, clamped)
    }

    fun updateVirtualJoystickInvertPan(value: Boolean) {
        virtualJoystickInvertPan = value
        OperatorPrefs.setVirtualJoystickInvertPan(appContext, value)
    }

    fun updateVirtualJoystickInvertTilt(value: Boolean) {
        virtualJoystickInvertTilt = value
        OperatorPrefs.setVirtualJoystickInvertTilt(appContext, value)
    }

    fun updateVirtualJoystickDeadzonePercent(value: Int) {
        val clamped = CameraCommands.VirtualJoystickMapping.clampedDeadzonePercent(value)
        virtualJoystickDeadzonePercent = clamped
        OperatorPrefs.setVirtualJoystickDeadzonePercent(appContext, clamped)
    }

    fun updateVirtualJoystickResponseCurve(value: CameraCommands.VirtualJoystickCurve) {
        virtualJoystickResponseCurve = value
        OperatorPrefs.setVirtualJoystickResponseCurve(appContext, value)
    }

    fun updateVirtualJoystickSize(value: com.opencapture.monitorui.MonitorJoystickSize) {
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

    fun updateCleanViewPinnedTools(value: Set<String>) {
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

    fun setAudioChannel(value: Int) = session.setAudioChannel(value)

    fun setVocalBoost(on: Boolean) = session.setVocalBoost(on)

    fun setWindNr(on: Boolean) = session.setWindNr(on)

    fun setDirectionalAudio(mode: Int) = session.setDirectionalAudio(mode)

    fun refreshAudio() = session.refreshAudio()

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

    fun updateGimbalPadStick(x: Float, y: Float) {
        if (uiLocked) return
        session.updateGimbalStick(x, y, gimbalStickSensitivity, assist.mirrorsHorizontally)
    }

    fun endGimbalStick() = session.endGimbalStick()

    val isLive: Boolean
        get() = shell.state.value.monitor != null

    fun canDriveGimbalPad(): Boolean =
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
                    val next = com.opencapture.openpocketcine.media.createLunaMediaLibrary(appContext, session, mediaStorage, service, scope)
                    mediaLibrary = next.first; mediaPlayback = next.second
                    scope.launch { retired.dispose() }
                } else if (mediaServiceID != service?.sessionID) mediaLibrary.bind(service)
                mediaServiceID = service?.sessionID
                if (connected != null) noteBecameLive()
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

    fun disconnect() {
        focusBoxLocked = false
        shell.close()
        session.disconnect()
    }

    fun close() {
        mediaLibrary.close()
        inspectorPreview.close()
        gimbalGamepad.stopListening()
        scope.cancel()
        // The activity ends: its camera session ends with it, without restarting discovery.
        shell.state.value.monitor?.session?.closeNow(SessionCloseReason.REQUESTED)
        session.close()
    }

    /** The tile's LUT choice travels into and out of its borrowed Live View. */
    fun setBorrowedLut(enabled: Boolean) {
        if (assist.lutOn != enabled) assist.toggle(com.opencapture.openpocketcine.assists.LiveAssistTool.LUT)
    }

    fun borrowedLutEnabled(): Boolean = assist.lutOn

    companion object {
        /** The records every earlier build reads, kept mirrored (SHELL-02 D11). */
        const val LEGACY_CAMERAS = "openpocketcine.saved-cameras"

        /** The saved-camera document over the legacy records, as this app stores them. */
        fun camerasStore(document: StoredString, legacy: StoredString) = SavedCamerasStore(
            document,
            SavedCamerasStore.Legacy(legacy, BodyRecordsV0(LunaFailures.INTEGRATION, BodyRecordsV0.Dates.EPOCH_MILLISECONDS), LEGACY_CAMERAS),
        )
    }
}
