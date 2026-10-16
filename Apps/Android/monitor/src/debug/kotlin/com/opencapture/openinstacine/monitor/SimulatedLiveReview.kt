package com.opencapture.openinstacine.monitor

import com.opencapture.monitorui.ReviewLiveValues
import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraRecordingFormat
import com.opencapture.opencine.core.CameraRecordingObservations
import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CameraTimecode
import com.opencapture.opencine.core.CommandReceipt
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.opencine.core.ControlAuthority
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.ObservedValue
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.StorageVolume
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.insta360.shell.CameraBackend
import com.opencapture.opencine.insta360.shell.CameraCapability
import com.opencapture.opencine.insta360.shell.CameraColorProfile
import com.opencapture.opencine.insta360.shell.CameraControls
import com.opencapture.opencine.insta360.shell.CameraExposure
import com.opencapture.opencine.insta360.shell.CameraFocusMode
import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import com.opencapture.opencine.insta360.shell.CameraGimbalMode
import com.opencapture.opencine.insta360.shell.CameraGimbalSpeed
import com.opencapture.opencine.insta360.shell.CameraIdentity
import com.opencapture.opencine.insta360.shell.CameraNotice
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraRecordFormat
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import com.opencapture.opencine.insta360.shell.CameraSnapshot as ShellSnapshot
import com.opencapture.opencine.insta360.shell.CameraStorage
import com.opencapture.opencine.insta360.shell.CameraTrackFrame
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import com.opencapture.opencine.insta360.shell.label
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow

/** The Luna recording colour the LIVE review stages (the iOS review stages I-Log too). */
internal val reviewLiveColor = CameraColorProfile.LOG

/** The shared LIVE review values as the Luna reports them (record format 48 is 4K 25p). */
internal fun reviewLiveReadout(values: ReviewLiveValues = ReviewLiveValues.SIMULATED): CameraReadout = CameraReadout(
    batteryPercent = values.batteryPercent,
    storages = listOf(CameraStorage(location = 2, usable = true, freeBytes = values.storageFreeBytes, totalBytes = values.storageTotalBytes)),
    shootingMode = CameraShootingMode.VIDEO,
    videoExposure = CameraExposure(program = 3, iso = values.iso, shutterSeconds = 1.0 / values.shutterDenominator),
    exposureBiasTenths = 0,
    whiteBalanceKelvin = values.whiteBalanceKelvin,
    color = reviewLiveColor,
    recordFormat = CameraRecordFormat(48, values.recordWidth, values.recordHeight, values.framesPerSecond.toDouble()),
    recordFormats = listOf(
        CameraRecordFormat(49, 3840, 2160, 24.0), CameraRecordFormat(48, 3840, 2160, 25.0),
        CameraRecordFormat(24, 3840, 2160, 30.0), CameraRecordFormat(52, 1920, 1080, 25.0),
    ),
    zoom = 1.0,
    gimbalMode = CameraGimbalMode.ROLL_LOCK,
    gimbalSpeed = CameraGimbalSpeed.MEDIUM,
    focusMode = CameraFocusMode.CONTINUOUS,
)

/**
 * Debug only, SIMULATED (`ReviewLaunch` LIVE): a Luna backend that is live from the start with the
 * shared review values. No radio, network, decoder or frames; every setter is refused.
 */
internal class SimulatedLiveBackend(values: ReviewLiveValues = ReviewLiveValues.SIMULATED) : CameraBackend, CameraControls {
    private val camera = CameraIdentity("review-simulated-1", "SIMULATED Luna Ultra", "Luna Ultra")
    override val capabilities = setOf(CameraCapability.LIVE_VIDEO, CameraCapability.ZOOM, CameraCapability.FOCUS)
    override val zoomRange = 1.0..15.0
    override val readout = MutableStateFlow(reviewLiveReadout(values))
    override val phase: StateFlow<ConnectionPhase> = MutableStateFlow(ConnectionPhase.LIVE)
    override val found = MutableStateFlow(listOf(camera))
    override val connected = MutableStateFlow<CameraIdentity?>(camera)
    override val snapshot = MutableStateFlow(ShellSnapshot(firmware = "SIMULATED", previewFps = values.framesPerSecond))
    override val failure = MutableStateFlow<String?>(null)
    override val radioOn = MutableStateFlow(true)
    override val joinedSSID = MutableStateFlow<String?>(null)
    override val frames: Flow<EncodedVideoFrame> = emptyFlow()
    override val trackFrames: Flow<CameraTrackFrame> = emptyFlow()
    override val notices: Flow<CameraNotice> = emptyFlow()
    override val gimbalHeadPitch: Double? = null
    override fun startScan() = Unit
    override fun connect(id: String) = Unit
    override fun disconnect() = Unit
    override fun close() = Unit
    override fun sceneActive(active: Boolean) = Unit
    override fun requestSettingsRefresh() = Unit
    override suspend fun setZoom(factor: Double) = false
    override suspend fun gimbalStick(pan: Double, tilt: Double) = false
    override suspend fun gimbalRecenter() = false
    override suspend fun gimbalFlip() = false
    override suspend fun tapFocus(x: Double, y: Double) = false
    override suspend fun startTracking(x: Double, y: Double, width: Double, height: Double) = false
    override suspend fun stopTracking() = false
    override suspend fun takePhoto() = false
    override suspend fun setExposureBias(thirds: Int) = false
    override suspend fun setColorProfile(profile: CameraColorProfile) = false
    override suspend fun setRecordFormat(id: Long) = false
    override suspend fun setShootingMode(mode: CameraShootingMode) = false
    override suspend fun setGimbalMode(mode: CameraGimbalMode) = false
    override suspend fun setGimbalSpeed(speed: CameraGimbalSpeed) = false
    override suspend fun setFocusMode(mode: CameraFocusMode) = false
    override suspend fun setFaceMetering(on: Boolean) = false
    override suspend fun gimbalAngle(): CameraGimbalAngle? = null
    override suspend fun gimbalSetAngle(pitch: Double, yaw: Double) = false
}

/**
 * Debug only, SIMULATED: the common session the LIVE review presents, reporting the shared review
 * values the way a connected Luna's session does (iOS reports them through `LunaCameraSession`).
 * Every command is refused.
 */
internal class ReviewLiveSession(values: ReviewLiveValues = ReviewLiveValues.SIMULATED) : CameraSession {
    override val id = CameraSessionID()
    private fun <T : Any> reported(value: T) = ObservedValue(value, ObservationOrigin.CAMERA_REPORTED, MonotonicInstant.ZERO)
    private val state = MutableStateFlow(
        com.opencapture.opencine.core.CameraSnapshot(
            session = id, epoch = ControlEpoch(1), connection = ConnectionState.Ready, authority = ControlAuthority.Owner,
            settings = mapOf(
                SettingKey.ISO to reported(SettingValue.Iso(ISOValue.Manual(values.iso))),
                SettingKey.SHUTTER to reported(SettingValue.Shutter(ShutterValue.Duration(Rational(1, values.shutterDenominator)))),
                SettingKey.WHITE_BALANCE to reported(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(values.whiteBalanceKelvin))),
                SettingKey.FRAME_RATE to reported(SettingValue.FrameRate(Rational(values.framesPerSecond, 1))),
            ),
            recording = reported(RecordingState.IDLE),
            power = PowerStatus(battery = reported(values.batteryPercent / 100.0)),
            storage = reported(listOf(StorageVolume("review-card", freeBytes = reported(values.storageFreeBytes),
                totalBytes = reported(values.storageTotalBytes)))),
            timecode = reported(CameraTimecode(values.timecodeHours, values.timecodeMinutes, values.timecodeSeconds, frames = 0)),
            recordingFormat = CameraRecordingObservations(
                dimensions = CameraRecordingFormat.Dimensions.measured(values.recordWidth, values.recordHeight)
                    ?.let(::reported) ?: ObservedValue.unknown,
                profile = reported(reviewLiveColor.label),
            ),
        ),
    )
    override val snapshots: StateFlow<com.opencapture.opencine.core.CameraSnapshot> = state
    override suspend fun submit(command: CameraCommand) =
        CommandReceipt(command.operation, id, command.intent, CommandStage.Rejected(CommandRejection.Unsupported))
    override suspend fun outcome(operation: OperationID): CommandReceipt? = null
    override fun receipt(operation: OperationID): CommandReceipt? = null
    override suspend fun close(reason: SessionCloseReason) = closeNow(reason)
    override fun closeNow(reason: SessionCloseReason) {
        state.value = state.value.copy(connection = ConnectionState.Disconnected(reason))
    }
}
