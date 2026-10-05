package com.opencapture.openpocketcine

import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.insta360.shell.CameraBackend
import com.opencapture.opencine.insta360.shell.CameraCapability
import com.opencapture.opencine.insta360.shell.CameraColorProfile
import com.opencapture.opencine.insta360.shell.CameraControls
import com.opencapture.opencine.insta360.shell.CameraFocusMode
import com.opencapture.opencine.insta360.shell.CameraGimbalAngle
import com.opencapture.opencine.insta360.shell.CameraGimbalMode
import com.opencapture.opencine.insta360.shell.CameraGimbalSpeed
import com.opencapture.opencine.insta360.shell.CameraIdentity
import com.opencapture.opencine.insta360.shell.CameraNotice
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import com.opencapture.opencine.insta360.shell.CameraSnapshot
import com.opencapture.opencine.insta360.shell.CameraTrackFrame
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import com.opencapture.openpocketcine.session.PocketCameraSession
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * A live Luna-shaped shell backend for session facade tests: records every control call with its
 * time and answers [accepts]; frames, track frames and notices are emitted by the test.
 */
internal class FakeShellBackend(
    override val capabilities: Set<CameraCapability> = setOf(
        CameraCapability.LIVE_VIDEO, CameraCapability.CAMERA_SETTINGS, CameraCapability.GIMBAL,
        CameraCapability.FOCUS, CameraCapability.TRACKING,
    ),
) : CameraBackend, CameraControls {
    data class Call(val name: String, val args: List<Any?>, val atMs: Long)

    val calls = CopyOnWriteArrayList<Call>()
    @Volatile var accepts = true
    @Volatile var angle: CameraGimbalAngle? = null

    fun calls(name: String) = calls.filter { it.name == name }

    private fun record(name: String, vararg args: Any?): Boolean {
        calls += Call(name, args.toList(), SystemClock.elapsedRealtime())
        return accepts
    }

    override val phase = MutableStateFlow(ConnectionPhase.LIVE)
    override val found = MutableStateFlow(emptyList<CameraIdentity>())
    override val connected = MutableStateFlow<CameraIdentity?>(CameraIdentity("LUNA-TEST", "Luna Ultra", "Insta360 Luna Ultra"))
    override val snapshot = MutableStateFlow(CameraSnapshot())
    override val failure = MutableStateFlow<String?>(null)
    override val radioOn = MutableStateFlow(true)
    override val joinedSSID = MutableStateFlow<String?>(null)
    val frameFlow = MutableSharedFlow<EncodedVideoFrame>(extraBufferCapacity = 64)
    override val frames = frameFlow
    override fun startScan() {}
    override fun connect(id: String) {}
    override fun disconnect() {}
    override fun close() {}
    override fun sceneActive(active: Boolean) {}

    override val zoomRange = 1.0..15.0
    override suspend fun setZoom(factor: Double) = record("setZoom", factor)
    override suspend fun gimbalStick(pan: Double, tilt: Double) = record("gimbalStick", pan, tilt)
    override suspend fun gimbalRecenter() = record("gimbalRecenter")
    override suspend fun gimbalFlip() = record("gimbalFlip")
    override suspend fun tapFocus(x: Double, y: Double) = record("tapFocus", x, y)
    override suspend fun startTracking(x: Double, y: Double, width: Double, height: Double) =
        record("startTracking", x, y, width, height)
    override suspend fun stopTracking() = record("stopTracking")
    override val readout = MutableStateFlow(CameraReadout())
    override suspend fun takePhoto() = record("takePhoto")
    override suspend fun setExposureBias(thirds: Int) = record("setExposureBias", thirds)
    override suspend fun setColorProfile(profile: CameraColorProfile) = record("setColorProfile", profile)
    override suspend fun setRecordFormat(id: Long) = record("setRecordFormat", id)
    override suspend fun setShootingMode(mode: CameraShootingMode) = record("setShootingMode", mode)
    override suspend fun setGimbalMode(mode: CameraGimbalMode) = record("setGimbalMode", mode)
    override suspend fun setGimbalSpeed(speed: CameraGimbalSpeed) = record("setGimbalSpeed", speed)
    override suspend fun setFocusMode(mode: CameraFocusMode) = record("setFocusMode", mode)
    override suspend fun setFaceMetering(on: Boolean) = record("setFaceMetering", on)
    override fun requestSettingsRefresh() { record("requestSettingsRefresh") }
    val trackFrameFlow = MutableSharedFlow<CameraTrackFrame>(extraBufferCapacity = 64)
    override val trackFrames = trackFrameFlow
    val noticeFlow = MutableSharedFlow<CameraNotice>(extraBufferCapacity = 16)
    override val notices = noticeFlow
    override suspend fun gimbalAngle(): CameraGimbalAngle? {
        record("gimbalAngle")
        return angle
    }
    override suspend fun gimbalSetAngle(pitch: Double, yaw: Double) = record("gimbalSetAngle", pitch, yaw)
    override val gimbalHeadPitch: Double? = null
}

/** Runs [block] on the main thread, where the session facade lives. */
internal fun <T> onMain(block: () -> T): T {
    if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) return block()
    var result: Result<T>? = null
    InstrumentationRegistry.getInstrumentation().runOnMainSync { result = runCatching(block) }
    return result!!.getOrThrow()
}

/** Polls [predicate] off the main thread until it holds or [timeoutMs] passes. */
internal fun waitUntil(timeoutMs: Long = 5_000, predicate: () -> Boolean): Boolean {
    val end = SystemClock.elapsedRealtime() + timeoutMs
    while (SystemClock.elapsedRealtime() < end) {
        if (onMain(predicate)) return true
        SystemClock.sleep(10)
    }
    return onMain(predicate)
}

/** A facade over [backend], as the brand launcher would build it. */
internal fun liveSession(backend: FakeShellBackend): PocketCameraSession {
    MonitorConfiguration.install(MonitorConfiguration.identity) { backend }
    return onMain { PocketCameraSession(InstrumentationRegistry.getInstrumentation().targetContext) }
}
