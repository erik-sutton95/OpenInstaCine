package com.opencapture.openinstacine.monitor

import com.opencapture.monitorui.ReviewLiveValues
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
import com.opencapture.opencine.insta360.shell.CameraSnapshot
import com.opencapture.opencine.insta360.shell.CameraStorage
import com.opencapture.opencine.insta360.shell.CameraTrackFrame
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow

/** The Luna recording colour the LIVE review stages (the iOS review stages I-Log too). */
public val reviewLiveColor: CameraColorProfile = CameraColorProfile.LOG

/** The shared review values as the Luna reports them (record format 48 is 4K 25p). */
public fun reviewLiveReadout(values: ReviewLiveValues = ReviewLiveValues.SIMULATED): CameraReadout = CameraReadout(
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
 * Debug only: the one Luna backend the review harnesses build on (the SIMULATED live review and the
 * private local replay). It reports the shared review values as a Luna does, owns no radio,
 * network or decoder, and refuses every command; a subclass adds frames and its own connection.
 */
public open class ReviewLunaBackend(
    protected val camera: CameraIdentity,
    initialPhase: ConnectionPhase,
    firmware: String,
    override val capabilities: Set<CameraCapability>,
    values: ReviewLiveValues = ReviewLiveValues.SIMULATED,
) : CameraBackend, CameraControls {
    override val zoomRange: ClosedFloatingPointRange<Double> = 1.0..15.0
    override val readout: MutableStateFlow<CameraReadout> = MutableStateFlow(reviewLiveReadout(values))
    override val phase: MutableStateFlow<ConnectionPhase> = MutableStateFlow(initialPhase)
    override val found: MutableStateFlow<List<CameraIdentity>> = MutableStateFlow(listOf(camera))
    override val connected: MutableStateFlow<CameraIdentity?> = MutableStateFlow(camera)
    override val snapshot: MutableStateFlow<CameraSnapshot> =
        MutableStateFlow(CameraSnapshot(firmware = firmware, previewFps = values.framesPerSecond))
    override val failure: MutableStateFlow<String?> = MutableStateFlow(null)
    override val radioOn: MutableStateFlow<Boolean> = MutableStateFlow(true)
    override val joinedSSID: MutableStateFlow<String?> = MutableStateFlow(null)
    open override val frames: Flow<EncodedVideoFrame> = emptyFlow()
    override val trackFrames: Flow<CameraTrackFrame> = emptyFlow()
    override val notices: Flow<CameraNotice> = emptyFlow()
    override val gimbalHeadPitch: Double? = null
    open override fun startScan() = Unit
    open override fun connect(id: String) = Unit
    open override fun disconnect() = Unit
    open override fun close() = Unit
    override fun sceneActive(active: Boolean) = Unit
    override fun requestSettingsRefresh() = Unit
    // No camera answers a command here.
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
