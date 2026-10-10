package com.opencapture.openinstacine

import android.content.Context
import com.opencapture.opencine.insta360.shell.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile

/** Debug-only UI/decoder verification. Private captures are never bundled with the app. */
class LocalReplayBackend(context: Context) : CameraBackend, CameraControls {
    private val directory = context.filesDir
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var started = false
    // Same capability set as LunaBackend so the replay shows the Luna chrome; no command reaches a camera.
    override val capabilities = setOf(
        CameraCapability.LIVE_VIDEO, CameraCapability.GIMBAL, CameraCapability.ZOOM,
        CameraCapability.FOCUS, CameraCapability.TRACKING,
    )
    override val zoomRange = 1.0..15.0
    override suspend fun setZoom(factor: Double) = false
    override suspend fun gimbalStick(pan: Double, tilt: Double) = false
    override suspend fun gimbalRecenter() = false
    override suspend fun gimbalFlip() = false
    override suspend fun tapFocus(x: Double, y: Double) = false
    override suspend fun startTracking(x: Double, y: Double, width: Double, height: Double) = false
    override suspend fun stopTracking() = false
    // No camera answers a command here; the replay advertises none of these capabilities.
    override suspend fun takePhoto() = false
    override suspend fun setExposureBias(thirds: Int) = false
    override suspend fun setColorProfile(profile: CameraColorProfile) = false
    override suspend fun setRecordFormat(id: Long) = false
    override suspend fun setShootingMode(mode: CameraShootingMode) = false
    override suspend fun setGimbalMode(mode: CameraGimbalMode) = false
    override suspend fun setGimbalSpeed(speed: CameraGimbalSpeed) = false
    override suspend fun setFocusMode(mode: CameraFocusMode) = false
    override suspend fun setFaceMetering(on: Boolean) = false
    override fun requestSettingsRefresh() = Unit
    override val trackFrames: Flow<CameraTrackFrame> = emptyFlow()
    override val notices: Flow<CameraNotice> = emptyFlow()
    override suspend fun gimbalAngle(): CameraGimbalAngle? = null
    override suspend fun gimbalSetAngle(pitch: Double, yaw: Double) = false
    override val gimbalHeadPitch: Double? = null
    // A fixed Luna-shaped readout so the live chrome shows mapped values; no camera answers the setters.
    override val readout = MutableStateFlow(
        CameraReadout(
            batteryPercent = 66,
            storages = listOf(CameraStorage(location = 2, usable = true, freeBytes = 42_100_000_000, totalBytes = 50_490_900_480)),
            shootingMode = CameraShootingMode.VIDEO,
            videoExposure = CameraExposure(program = 3, iso = 400, shutterSeconds = 1.0 / 50),
            exposureBiasTenths = 0,
            whiteBalanceKelvin = 5600,
            color = CameraColorProfile.LOG,
            recordFormat = CameraRecordFormat(48, 3840, 2160, 25.0),
            recordFormats = listOf(
                CameraRecordFormat(49, 3840, 2160, 24.0), CameraRecordFormat(48, 3840, 2160, 25.0),
                CameraRecordFormat(24, 3840, 2160, 30.0), CameraRecordFormat(52, 1920, 1080, 25.0),
            ),
            zoom = 1.0,
            gimbalMode = CameraGimbalMode.ROLL_LOCK,
            gimbalSpeed = CameraGimbalSpeed.MEDIUM,
            focusMode = CameraFocusMode.CONTINUOUS,
        ),
    )
    private val camera = CameraIdentity("local-replay", "LOCAL REPLAY — Luna Ultra", "Luna recording · not a live camera")
    override val phase = MutableStateFlow(ConnectionPhase.IDLE)
    override val found = MutableStateFlow(listOf(camera))
    override val connected = MutableStateFlow<CameraIdentity?>(camera)
    override val snapshot = MutableStateFlow(CameraSnapshot(firmware = "LOCAL REPLAY", previewFps = 25))
    override val failure = MutableStateFlow<String?>(null)
    override val radioOn = MutableStateFlow(true)
    override val joinedSSID = MutableStateFlow<String?>(null)
    private val video = MutableSharedFlow<EncodedVideoFrame>(extraBufferCapacity = 2)
    override val frames = video.asSharedFlow()
    override fun startScan() { if (!started) { started = true; connect(camera.id) } else if (job?.isActive != true) phase.value = ConnectionPhase.SCANNING }
    override fun connect(id: String) {
        job?.cancel()
        job = scope.launch {
            try {
                val index = JSONObject(File(directory, "review-preview-index.json").readText())
                val packets = index.getJSONArray("packets")
                val fps = index.getInt("framesPerSecond")
                require(fps in 1..120 && packets.length() > 0)
                val file = File(directory, "review-preview.hevc")
                require(file.isFile && file.length() <= 128L * 1024 * 1024)
                phase.value = ConnectionPhase.LIVE
                delay(1_500)
                RandomAccessFile(file, "r").use { videoFile ->
                    while (isActive) {
                        val began = System.nanoTime()
                        for (i in 0 until packets.length()) {
                            ensureActive()
                            val packet = packets.getJSONObject(i)
                            val offset = packet.getLong("offset"); val size = packet.getInt("size")
                            require(offset >= 0 && size in 1..(4 * 1024 * 1024) && offset + size <= videoFile.length())
                            val bytes = ByteArray(size); videoFile.seek(offset); videoFile.readFully(bytes)
                            video.emit(EncodedVideoFrame(bytes, System.nanoTime() / 1000))
                            val remaining = began + (i + 1L) * 1_000_000_000L / fps - System.nanoTime()
                            if (remaining > 0) delay(remaining / 1_000_000L)
                        }
                    }
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { failure.value = "Local replay requires private review-preview.hevc and review-preview-index.json in app files."; phase.value = ConnectionPhase.FAILED }
        }
    }
    override fun disconnect() { job?.cancel(); phase.value = ConnectionPhase.IDLE }
    override fun close() { disconnect(); scope.cancel() }
    override fun sceneActive(active: Boolean) = Unit
}
