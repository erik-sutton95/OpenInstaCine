package com.opencapture.openpocketcine.core

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

public enum class ConnectionPhase { IDLE, SCANNING, CONNECTING_GATT, PAIRING, AWAITING_APPROVAL, READING_WIFI_CREDS, JOINING_WIFI, OPENING_DATALINK, LIVE, FAILED }
public enum class CameraCapability { LIVE_VIDEO, CAMERA_SETTINGS, RECORD, GIMBAL, FOCUS, CAMERA_MEDIA, AUDIO, ZOOM, TRACKING }
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
 public suspend fun tapFocus(x: Double, y: Double): Boolean
 public suspend fun startTracking(x: Double, y: Double, width: Double, height: Double): Boolean
 public suspend fun stopTracking(): Boolean
}

/** Compatibility surface for inherited shell code during the shared engine extraction. */
public interface CameraSession { public val phase: ConnectionPhase; public fun startScan(); public fun disconnect() }
