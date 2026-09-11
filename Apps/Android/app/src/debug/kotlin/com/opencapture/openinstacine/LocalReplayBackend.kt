package com.opencapture.openinstacine

import android.content.Context
import com.opencapture.openpocketcine.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile

/** Debug-only UI/decoder verification. Private captures are never bundled with the app. */
class LocalReplayBackend(context: Context) : CameraBackend {
    private val directory = context.filesDir
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var started = false
    override val capabilities = setOf(CameraCapability.LIVE_VIDEO)
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
