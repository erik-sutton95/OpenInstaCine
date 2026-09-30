package com.opencapture.openpocketcine.core

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

public enum class ConnectionPhase { IDLE, SCANNING, CONNECTING_GATT, PAIRING, AWAITING_APPROVAL, READING_WIFI_CREDS, JOINING_WIFI, OPENING_DATALINK, LIVE, FAILED }
public enum class CameraCapability { LIVE_VIDEO, CAMERA_SETTINGS, RECORD, GIMBAL, FOCUS, CAMERA_MEDIA, AUDIO, ZOOM, TRACKING, METERED_EV, NATIVE_ISO_HOP }
public data class CameraIdentity(public val id: String, public val advertisedName: String, public val modelName: String)
public data class CameraSnapshot(public val firmware: String? = null, public val batteryPercent: Int? = null, public val previewWidth: Int = 1280, public val previewHeight: Int = 720, public val previewFps: Int = 25)
public data class EncodedVideoFrame(public val annexB: ByteArray, public val timestampMicros: Long)
public data class BrandIdentity(public val appName: String, public val wordmark: String, public val accentArgb: Long, public val cameraFamily: String, public val sourceUrl: String? = null, public val supportUrl: String? = null, public val issueUrl: String? = null, public val featureUrl: String? = null, public val sourceLabel: String? = null)

/** Backend owns camera protocol and connection I/O. Shared monitor owns decode and UI. */
public interface CameraBackend {
 public val capabilities: Set<CameraCapability>
 public val phase: StateFlow<ConnectionPhase>
 public val found: StateFlow<List<CameraIdentity>>
 public val connected: StateFlow<CameraIdentity?>
 public val snapshot: StateFlow<CameraSnapshot>
 public val failure: StateFlow<String?>
 public val radioOn: StateFlow<Boolean>
 public val joinedSSID: StateFlow<String?>
 public val frames: Flow<EncodedVideoFrame>
 public fun startScan()
 public fun connect(id: String)
 public fun disconnect()
 public fun close()
 public fun sceneActive(active: Boolean)
}

/**
 * Optional live camera controls. A backend implements this only for commands it has verified;
 * the shared session gates each control on [CameraBackend.capabilities]. Coordinates are
 * normalized 0..1 in the displayed live frame. Each call returns false when the camera rejected
 * the command or no control link is up.
 */
public interface CameraControls {
 public val zoomRange: ClosedFloatingPointRange<Double>
 public suspend fun setZoom(factor: Double): Boolean
 /** Rate stick, each axis -1..1. A zero stick releases the gimbal. */
 public suspend fun gimbalStick(pan: Double, tilt: Double): Boolean
 public suspend fun gimbalRecenter(): Boolean
 public suspend fun gimbalFlip(): Boolean
 /** [x], [y]: the tapped point; the backend sizes its focus region around it and keeps it in frame. */
 public suspend fun tapFocus(x: Double, y: Double): Boolean
 public suspend fun startTracking(x: Double, y: Double, width: Double, height: Double): Boolean
 public suspend fun stopTracking(): Boolean

 // Capture, exposure and settings. Defaults mean "not supported"; readout stays empty.
 public val readout: StateFlow<CameraReadout> get() = CameraReadout.NONE
 public suspend fun startRecording(): Boolean = false
 public suspend fun stopRecording(): Boolean = false
 public suspend fun takePhoto(): Boolean = false
 /** Null ISO / shutter means the camera chooses that value; the backend picks its program. */
 public suspend fun setExposure(iso: Int?, shutterSeconds: Double?): Boolean = false
 public suspend fun setExposureBias(thirds: Int): Boolean = false
 /** Null kelvin is auto white balance. */
 public suspend fun setWhiteBalance(kelvin: Int?): Boolean = false
 public suspend fun setColorProfile(profile: CameraColorProfile): Boolean = false
 /** [id] is a [CameraRecordFormat.id] from the readout. */
 public suspend fun setRecordFormat(id: Long): Boolean = false
 public suspend fun setShootingMode(mode: CameraShootingMode): Boolean = false
 public suspend fun setGimbalMode(mode: CameraGimbalMode): Boolean = false
 public suspend fun setGimbalSpeed(speed: CameraGimbalSpeed): Boolean = false
 public suspend fun setFocusMode(mode: CameraFocusMode): Boolean = false
 /** True Face Priority metering, false Matrix. */
 public suspend fun setFaceMetering(on: Boolean): Boolean = false
 /** Re-read settings shortly after a burst of writes. */
 public fun requestSettingsRefresh() {}
 /** The camera's own subject tracking, from the live stream; only changes are delivered. */
 public val trackFrames: Flow<CameraTrackFrame> get() = kotlinx.coroutines.flow.emptyFlow()
 /** Absolute head angle in the handle frame (Luna GET_ANGLE), or null when unavailable. */
 public suspend fun gimbalAngle(): CameraGimbalAngle? = null
 /** Aim the head at an absolute handle-frame angle (Luna SET_ANGLE); the latest request wins. */
 public suspend fun gimbalSetAngle(pitch: Double, yaw: Double): Boolean = false
 /** Head world pitch from the camera IMU in degrees (up positive), or null without a sample in the last 0.3 s. */
 public val gimbalHeadPitch: Double? get() = null
}

/** Degrees: pitch up positive, yaw as the camera reports it (-180..180). */
public data class CameraGimbalAngle(public val pitch: Double, public val yaw: Double)

public enum class CameraTrackState { TRACKING, LOST, IDLE }
/** Tracking state and the camera's box, top-left fractions of the preview. */
public data class CameraTrackFrame(public val state: CameraTrackState, public val x: Double, public val y: Double, public val width: Double, public val height: Double)

public enum class CameraShootingMode { VIDEO, TIMELAPSE, TIMESHIFT, SLOW_MOTION, PURE_VIDEO, PHOTO, PANO }
public enum class CameraColorProfile { STANDARD, LOG, VIVID, HDR, DOLBY_VISION }
public enum class CameraGimbalMode { FPV, ROLL_LOCK, ROLL_TILT_LOCK, FPV_VERTICAL, LOCK, STABILIZED_VERTICAL }
public enum class CameraGimbalSpeed { SLOW, MEDIUM, FAST, SENSITIVE }
public enum class CameraFocusMode { SINGLE, CONTINUOUS, PRODUCT_SHOWCASE }

/** [program]: 0 auto, 1 ISO priority, 2 shutter priority, 3 manual, 4 adaptive, 5 full auto. ISO 0 / shutter 0 = camera chooses. */
public data class CameraExposure(public val program: Int, public val iso: Int, public val shutterSeconds: Double)
/** One recordable frame size and rate; [id] is the backend's own value for it. */
public data class CameraRecordFormat(public val id: Long, public val width: Int, public val height: Int, public val fps: Double)
/** [location] 2 camera inner storage, 3 SD card. */
public data class CameraStorage(public val location: Int, public val usable: Boolean, public val freeBytes: Long, public val totalBytes: Long)

/** What the camera last reported. Null fields have not been reported yet. */
public data class CameraReadout(
 public val batteryPercent: Int? = null,
 public val charging: Boolean = false,
 public val storages: List<CameraStorage> = emptyList(),
 public val shootingMode: CameraShootingMode? = null,
 public val recording: Boolean = false,
 public val captureSeconds: Int = 0,
 public val videoExposure: CameraExposure? = null,
 public val stillExposure: CameraExposure? = null,
 public val exposureBiasTenths: Int? = null,
 /** 0 is auto. */
 public val whiteBalanceKelvin: Int? = null,
 public val color: CameraColorProfile? = null,
 public val recordFormat: CameraRecordFormat? = null,
 /** Formats the operator may pick. Empty until settings are read. */
 public val recordFormats: List<CameraRecordFormat> = emptyList(),
 public val zoom: Double? = null,
 public val gimbalMode: CameraGimbalMode? = null,
 public val gimbalSpeed: CameraGimbalSpeed? = null,
 /** Null also when the camera reports a mode the shell does not offer. */
 public val focusMode: CameraFocusMode? = null,
 /** True Face Priority metering, false Matrix. */
 public val faceMetering: Boolean? = null,
) {
 public companion object { public val NONE: StateFlow<CameraReadout> = kotlinx.coroutines.flow.MutableStateFlow(CameraReadout()) }
}

/** One camera file. [path] addresses it for thumbnail, delete and HTTP. */
public data class CameraMediaItem(
 public val path: String,
 public val proxyPath: String? = null,
 public val sizeBytes: Long = 0,
 public val durationSeconds: Int = 0,
 public val width: Int? = null,
 public val height: Int? = null,
 public val fps: Int? = null,
 /** Camera's gamma name, e.g. "standard" or "log". */
 public val gamma: String? = null,
)

/** Optional camera media over the control link. Every call throws when it fails. */
public interface CameraMediaStore {
 public suspend fun listMedia(): List<CameraMediaItem>
 public suspend fun thumbnailJpeg(path: String): ByteArray
 public suspend fun deleteMedia(path: String)
 /** Stop live video while the album is open so HTTP has the link. */
 public suspend fun pauseLive()
 public suspend fun resumeLive()
}

/** Compatibility surface for inherited shell code during the shared engine extraction. */
public interface CameraSession { public val phase: ConnectionPhase; public fun startScan(); public fun disconnect() }
