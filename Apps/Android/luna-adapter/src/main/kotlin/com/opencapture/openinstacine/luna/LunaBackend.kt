package com.opencapture.openinstacine.luna

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.ParcelUuid
import com.opencapture.openpocketcine.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.*
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID

/** Luna transport, status and controls. No Compose, packet logs, or saved passwords. */
@SuppressLint("MissingPermission")
class LunaBackend(context: Context) : CameraBackend, CameraControls, CameraMediaStore {
    private val context = context.applicationContext
    private val bluetooth = context.getSystemService(BluetoothManager::class.java)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val preferences = context.getSharedPreferences("openinstacine.client-identity", Context.MODE_PRIVATE)
    private val clientIdentity: String = preferences.getString("authorization-id", null) ?: UUID.randomUUID().toString().uppercase().also { preferences.edit().putString("authorization-id", it).apply() }
    override val capabilities = setOf(
        CameraCapability.LIVE_VIDEO, CameraCapability.GIMBAL, CameraCapability.ZOOM,
        CameraCapability.FOCUS, CameraCapability.TRACKING, CameraCapability.CAMERA_SETTINGS,
        CameraCapability.RECORD, CameraCapability.CAMERA_MEDIA,
    )
    private val _phase = MutableStateFlow(ConnectionPhase.IDLE)
    override val phase = _phase.asStateFlow()
    private val _found = MutableStateFlow<List<CameraIdentity>>(emptyList())
    override val found = _found.asStateFlow()
    private val _connected = MutableStateFlow<CameraIdentity?>(null)
    override val connected = _connected.asStateFlow()
    private val _snapshot = MutableStateFlow(CameraSnapshot())
    override val snapshot = _snapshot.asStateFlow()
    private val _failure = MutableStateFlow<String?>(null)
    override val failure = _failure.asStateFlow()
    private val _radioOn = MutableStateFlow(bluetooth?.adapter?.isEnabled == true)
    override val radioOn = _radioOn.asStateFlow()
    private val _joinedSSID = MutableStateFlow<String?>(null)
    override val joinedSSID = _joinedSSID.asStateFlow()
    private val video = MutableSharedFlow<EncodedVideoFrame>(extraBufferCapacity = 8, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val frames: Flow<EncodedVideoFrame> = video.asSharedFlow()
    private val trackFlow = MutableSharedFlow<CameraTrackFrame>(extraBufferCapacity = 8, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val trackFrames: Flow<CameraTrackFrame> = trackFlow.asSharedFlow()
    private val noticeFlow = MutableSharedFlow<CameraNotice>(extraBufferCapacity = 8, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val notices: Flow<CameraNotice> = noticeFlow.asSharedFlow()
    /** Receive thread only. The camera repeats the frame with every video frame; only changes go out. */
    private var lastTrack: LunaTrackFrame? = null
    private var connectJob: Job? = null
    private var scanActive = false
    @Volatile private var socket: Socket? = null
    @Volatile private var tcp: LunaChannel? = null
    private var gatt: LunaGatt? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wasInactive = false
    private var boundNetwork = false
    // Status, merged across partial reads like the iOS session. Main thread only.
    private var settings: LunaPhotographySettings? = null
    private var device: LunaDeviceStatus? = null
    private var capture: LunaCaptureStatus? = null
    /** Active shooting mode (video until the camera says otherwise); its settings bank is [functionMode]. */
    private var mode = LunaShootingMode.VIDEO
    private val functionMode get() = mode.functionMode
    private var settingsRefresh: Job? = null
    private val _readout = MutableStateFlow(CameraReadout())
    override val readout = _readout.asStateFlow()
    private val lastVideoAt = java.util.concurrent.atomic.AtomicLong()
    /** Live video is stopped on purpose while the album is open; the watchdog must not fire. */
    @Volatile private var livePaused = false
    private val scanner = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val record = result.scanRecord ?: return
            if (record.serviceUuids?.contains(ParcelUuid(LunaGatt.SERVICE)) != true) return
            val name = record.deviceName ?: result.device.name ?: "Luna Ultra"
            val identity = CameraIdentity(result.device.address, name, "Insta360 Luna Ultra")
            _found.update { cameras -> (cameras.filterNot { it.id == identity.id } + identity).sortedBy { it.advertisedName } }
        }
        override fun onScanFailed(code: Int) { scanActive = false; _failure.value = "Bluetooth scanning could not start ($code). Check Nearby devices permission."; _phase.value = ConnectionPhase.FAILED }
    }
    override fun startScan() {
        if (connectJob?.isActive == true) return
        _radioOn.value = bluetooth?.adapter?.isEnabled == true
        if (!_radioOn.value) { _phase.value = ConnectionPhase.IDLE; return }
        _failure.value = null
        stopScan()
        try {
            bluetooth.adapter.bluetoothLeScanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(LunaGatt.SERVICE)).build()), ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scanner)
            scanActive = true; _phase.value = ConnectionPhase.SCANNING
        } catch (_: SecurityException) { _failure.value = "Allow Nearby devices and location access to discover your camera."; _phase.value = ConnectionPhase.FAILED }
    }
    private fun stopScan() { if (scanActive) runCatching { bluetooth?.adapter?.bluetoothLeScanner?.stopScan(scanner) }; scanActive = false }
    override fun connect(id: String) {
        val previous = connectJob
        previous?.cancel()
        socket?.close()
        stopScan()
        connectJob = scope.launch {
            previous?.join()
            _failure.value = null
            _connected.value = _found.value.firstOrNull { it.id == id } ?: CameraIdentity(id, "Luna Ultra", "Insta360 Luna Ultra")
            try { runCamera(id) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) {
                _failure.value = when (_phase.value) {
                    ConnectionPhase.AWAITING_APPROVAL -> "Camera approval was not completed. Wake Luna and accept the connection on its screen."
                    ConnectionPhase.JOINING_WIFI -> "Could not join Luna Wi-Fi. Keep the camera awake and accept Android's Wi-Fi connection request."
                    ConnectionPhase.LIVE -> "The camera feed disconnected. Wake Luna and tap Retry."
                    ConnectionPhase.OPENING_DATALINK -> "The camera Wi-Fi connected, but live view did not start. Close the Insta360 app and try again."
                    else -> "Could not connect to Luna. Keep it awake, close the Insta360 app, and try again."
                }
                _phase.value = ConnectionPhase.FAILED
            } finally { cleanup() }
        }
    }
    private suspend fun runCamera(id: String): Unit = coroutineScope {
        _phase.value = ConnectionPhase.CONNECTING_GATT
        val ble = LunaGatt(context); gatt = ble
        ble.connect(checkNotNull(bluetooth?.adapter).getRemoteDevice(id))
        val link = ble.channel
        val initial = LunaWire.bytes(link.request(8, LunaWire.options(48, 30)), 2)
        check(LunaWire.text(initial, 48) == "Insta360 Luna Ultra") { "Unexpected camera model" }
        _snapshot.value = CameraSnapshot(firmware = LunaWire.text(initial, 30))
        _phase.value = ConnectionPhase.PAIRING
        val schemes = LunaWire.schemes(link.request(240))
        check(3L in schemes) { "AES-GCM is not supported" }
        val pair = LunaWire.keyPair()
        link.key = LunaWire.exchange(pair, link.request(241, LunaWire.integer(1, 3) + LunaWire.blob(2, LunaWire.publicBytes(pair))))
        val verified = LunaWire.bytes(link.request(8, LunaWire.options(48, 30), encrypted = true), 2)
        check(LunaWire.text(verified, 48) == "Insta360 Luna Ultra")
        val identity = clientIdentity.toByteArray()
        // Initiator 1 follows the hardware-verified bootstrap; IDs are this installation's own.
        val authBody = LunaWire.blob(1, identity) + LunaWire.integer(2, 1) + LunaWire.blob(3, identity)
        when (LunaWire.number(link.request(39, authBody), 1)) {
            0L -> Unit
            1L -> {
                _phase.value = ConnectionPhase.AWAITING_APPROVAL
                link.request(86, LunaWire.integer(1, 1))
                withTimeout(120_000) {
                    while (true) {
                        val approval = link.approvals.receive()
                        if (LunaWire.number(approval.body, 2) !in 0L..1L) continue
                        check(LunaWire.number(approval.body, 1) == 0L) { "Camera did not approve this client" }; break
                    }
                }
            }
            else -> error("Unknown camera authorization result")
        }
        _phase.value = ConnectionPhase.READING_WIFI_CREDS
        val wifi = LunaWire.bytes(LunaWire.bytes(link.request(8, LunaWire.options(36, 37, 43), encrypted = true), 2), 36)
        val ssid = LunaWire.text(wifi, 1); val password = LunaWire.text(wifi, 2)
        check(ssid.isNotBlank() && password.length in 8..63)
        ble.close(); gatt = null
        _phase.value = ConnectionPhase.JOINING_WIFI
        val network = joinNetwork(ssid, password)
        _joinedSSID.value = ssid
        // Media HTTP (192.168.42.1:80) goes through the shared OkHttp client, as upstream binds for DJI.
        boundNetwork = connectivity.bindProcessToNetwork(network)
        _phase.value = ConnectionPhase.OPENING_DATALINK
        val cameraSocket = withContext(Dispatchers.IO) {
            network.socketFactory.createSocket().also { socket = it; it.tcpNoDelay = true; it.soTimeout = 10_000; it.connect(InetSocketAddress("192.168.42.1", 6666), 8_000) }
        }
        lastVideoAt.set(android.os.SystemClock.elapsedRealtime())
        val channel = LunaChannel(
            send = { bytes -> withContext(Dispatchers.IO) { cameraSocket.getOutputStream().write(bytes); cameraSocket.getOutputStream().flush() } },
            video = { bytes, tick -> lastVideoAt.set(android.os.SystemClock.elapsedRealtime()); video.tryEmit(EncodedVideoFrame(bytes, tick)) },
            notify = { message -> val note = LunaNotification.parse(message.code, message.body); scope.launch { handle(note) } },
            track = { frame -> if (frame != lastTrack) { lastTrack = frame; frame.shared?.let(trackFlow::tryEmit) } },
            imu = { samples ->
                val now = android.os.SystemClock.elapsedRealtime()
                synchronized(headPitch) { headPitch.ingest(samples, commanding = now - gimbalCommandAt < 500) }
                imuAt = now
            },
        )
        lastTrack = null
        tcp = channel
        val receiver = launch(Dispatchers.IO) {
            try {
                val buffer = ByteArray(65536)
                while (isActive) {
                    val count = cameraSocket.getInputStream().read(buffer)
                    check(count >= 0) { "Camera closed TCP" }
                    if (count > 0) channel.receive(buffer.copyOf(count))
                }
            } catch (error: Exception) { channel.fail(error) }
        }
        var heartbeat: Job? = null
        var watchdog: Job? = null
        var poll: Job? = null
        try {
            channel.raw(LunaWire.prefix)
            withTimeout(8_000) { channel.greeting.await() }
            heartbeat = launch { try { while (isActive) { channel.heartbeat(); delay(2_000) } } catch (error: Exception) { channel.fail(error) } }
            val tcpInfo = LunaWire.bytes(channel.request(8, LunaWire.options(48, 30)), 2)
            check(LunaWire.text(tcpInfo, 48) == "Insta360 Luna Ultra")
            check(LunaWire.number(channel.request(39, authBody), 1) == 0L) { "TCP identity was not authorized" }
            channel.request(15)
            _phase.value = ConnectionPhase.LIVE
            // Mount the inherited decoder/render host before asking for the first keyframe.
            delay(350)
            // Shooting view first: without it the gimbal stays asleep pointing down.
            val wake = LunaControl.accessCameraFileState(LunaControl.SHOOTING_VIEW_ACCESS_STATE)
            runCatching { channel.request(wake.code, wake.body) }
            channel.request(1, LunaWire.liveBody)
            lastVideoAt.set(android.os.SystemClock.elapsedRealtime())
            launch { syncClock() }
            watchdog = launch { while (isActive) { delay(2_000); if (!livePaused && android.os.SystemClock.elapsedRealtime() - lastVideoAt.get() > 10_000) { channel.fail(IllegalStateException("No live video received")); break } } }
            // Same cadence as iOS: capture state every second (REC timer), battery and storage every 5 s.
            poll = launch {
                refreshStatus()
                var tick = 0
                while (isActive) {
                    delay(1_000)
                    tick += 1
                    call(LunaControl.captureStatus)?.let { runCatching { LunaCaptureStatus.fromResponse(it) }.getOrNull() }?.let(::applyCapture)
                    if (tick % 5 == 0) refreshDevice(LunaControl.statusRequest)
                }
            }
            throw channel.failure.await()
        } finally {
            withContext(NonCancellable) { withTimeoutOrNull(1_500) { runCatching { channel.request(2) } } }
            poll?.cancel(); watchdog?.cancel(); heartbeat?.cancel(); cameraSocket.close(); receiver.cancel(); channel.close(); tcp = null
            settingsRefresh?.cancel(); livePaused = false
            settings = null; device = null; capture = null; mode = LunaShootingMode.VIDEO; publish()
        }
    }
    private suspend fun joinNetwork(ssid: String, password: String): Network {
        val ready = CompletableDeferred<Network>()
        val specifier = WifiNetworkSpecifier.Builder().setSsid(ssid).setWpa2Passphrase(password).build()
        val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(specifier).build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { ready.complete(network) }
            override fun onUnavailable() { ready.completeExceptionally(IllegalStateException("Wi-Fi request unavailable")) }
            override fun onLost(network: Network) { tcp?.fail(IllegalStateException("Camera Wi-Fi disconnected")) }
        }
        networkCallback = callback
        connectivity.requestNetwork(request, callback, 90_000)
        return withTimeout(95_000) { ready.await() }
    }
    private fun cleanup() {
        gatt?.close(); gatt = null
        runCatching { socket?.close() }; socket = null
        if (boundNetwork) { connectivity.bindProcessToNetwork(null); boundNetwork = false }
        networkCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }; networkCallback = null
        _joinedSSID.value = null
    }
    override fun disconnect() { stopScan(); connectJob?.cancel(); runCatching { socket?.close() }; _phase.value = ConnectionPhase.IDLE; _failure.value = null }
    override fun close() { disconnect(); cleanup(); scope.cancel() }
    override fun sceneActive(active: Boolean) {
        if (!active) { wasInactive = true; return }
        if (wasInactive && _phase.value == ConnectionPhase.FAILED) _connected.value?.let { connect(it.id) }
        wasInactive = false
    }

    // Status. Same reads as iOS `LunaCameraBackend.refreshStatus` and its notification handling.
    private suspend fun call(request: LunaControl.Request): ByteArray? {
        val channel = tcp ?: return null
        return runCatching { channel.request(request.code, request.body) }.getOrNull()
    }
    /**
     * iOS `syncCameraClock`: the Luna's timecode is time of day from its own clock. Set it like the
     * official app on connect (options 12/13/175), then to the millisecond with cmd 214, twice,
     * each stamped at send (a GET round trip on the camera AP is about 4 ms).
     */
    private suspend fun syncClock() {
        val zone = java.util.TimeZone.getDefault()
        val now = System.currentTimeMillis()
        call(LunaControl.setClock(now / 1000, zone.getOffset(now) / 1000, zone.id)) ?: return
        for (count in 0..1) call(LunaControl.syncTimeAccurate(System.currentTimeMillis(), count))
        android.util.Log.i("LunaBackend", "luna: camera clock synced")
    }
    private fun publish() { _readout.value = LunaReadout.readout(settings, device, capture) }
    private fun applyDevice(status: LunaDeviceStatus) {
        device = device?.merge(status) ?: status
        status.shootingMode?.let { mode = it }
        publish()
    }
    private fun applySettings(update: LunaPhotographySettings) {
        // A reply for another bank (a mode change in flight) is not this mode's settings.
        if (update.functionMode != null && update.functionMode != functionMode) return
        settings = settings?.merge(update) ?: update
        publish()
    }
    private fun applyCapture(status: LunaCaptureStatus) { capture = status; publish() }
    private suspend fun refreshDevice(request: LunaControl.Request) {
        call(request)?.let { runCatching { LunaDeviceStatus.parse(it) }.getOrNull() }?.let(::applyDevice)
    }
    private suspend fun refreshSettings() {
        call(LunaControl.getPhotographyOptions(LunaControl.settingTypes, functionMode))
            ?.let { runCatching { LunaPhotographySettings.parse(it) }.getOrNull() }?.let(::applySettings)
    }
    /** One full read: device status, the active mode (so the right settings bank), settings, capture state. */
    private suspend fun refreshStatus() {
        refreshDevice(LunaControl.statusRequest)
        refreshDevice(LunaControl.shootingModeRequest)
        refreshSettings()
        call(LunaControl.captureStatus)?.let { runCatching { LunaCaptureStatus.fromResponse(it) }.getOrNull() }?.let(::applyCapture)
    }
    private suspend fun handle(note: LunaNotification) {
        when (note) {
            is LunaNotification.Capture -> applyCapture(note.status)
            // iOS `applyTrackingState`: 1 / 2 locked, anything else ended (the camera cancelled it).
            is LunaNotification.Tracking -> noticeFlow.tryEmit(CameraNotice.Tracking(note.state == 1L || note.state == 2L))
            // Capture ended on the camera: re-read the capture state now so REC clears without waiting for the poll.
            is LunaNotification.CaptureStopped -> {
                noticeFlow.tryEmit(CameraNotice.CaptureStopped(note.errorCode))
                call(LunaControl.captureStatus)?.let { runCatching { LunaCaptureStatus.fromResponse(it) }.getOrNull() }?.let(::applyCapture)
            }
            is LunaNotification.PhotographyChanged -> applySettings(note.settings)
            // The notice carries a partial view; re-read the whole status.
            is LunaNotification.SubMode, is LunaNotification.Storage, is LunaNotification.Battery -> {
                refreshDevice(LunaControl.statusRequest)
                refreshDevice(LunaControl.shootingModeRequest)
                refreshSettings()
            }
            else -> Unit
        }
    }
    override fun requestSettingsRefresh() {
        settingsRefresh?.cancel()
        settingsRefresh = scope.launch { delay(400); refreshSettings() }
    }

    // Controls. Same requests as the iOS session; each needs the live TCP control channel.
    override val zoomRange: ClosedFloatingPointRange<Double> = 1.0..LunaControl.MAXIMUM_ZOOM
    private suspend fun send(build: () -> LunaControl.Request): Boolean {
        val channel = tcp ?: return false
        if (_phase.value != ConnectionPhase.LIVE) return false
        val request = runCatching(build).getOrElse { return false }
        return runCatching { channel.request(request.code, request.body) }.isSuccess
    }
    override suspend fun setZoom(factor: Double) = send { LunaControl.zoom(factor.coerceIn(zoomRange), functionMode) }
    override suspend fun gimbalStick(pan: Double, tilt: Double): Boolean {
        if (pan != 0.0 || tilt != 0.0) gimbalCommandAt = android.os.SystemClock.elapsedRealtime()
        return send { LunaControl.gimbalStick(pan, tilt) }
    }
    // iOS: GET_ANGLE with a 1 s timeout, SET_ANGLE fire and forget within 2 s.
    override suspend fun gimbalAngle(): CameraGimbalAngle? {
        val channel = tcp?.takeIf { _phase.value == ConnectionPhase.LIVE } ?: return null
        val request = LunaControl.gimbalGetAngle
        val reply = withTimeoutOrNull(1_000) { runCatching { channel.request(request.code, request.body) }.getOrNull() } ?: return null
        return runCatching { LunaControl.gimbalAngle(reply) }.getOrNull()?.let { CameraGimbalAngle(it.pitch.toDouble(), it.yaw.toDouble()) }
    }
    override suspend fun gimbalSetAngle(pitch: Double, yaw: Double): Boolean {
        gimbalCommandAt = android.os.SystemClock.elapsedRealtime()
        return withTimeoutOrNull(2_000) { send { LunaControl.gimbalSetAngle(pitch.toFloat(), yaw.toFloat()) } } ?: false
    }
    private val headPitch = LunaHeadPitch()
    @Volatile private var imuAt = 0L
    @Volatile private var gimbalCommandAt = 0L
    override val gimbalHeadPitch: Double?
        get() = synchronized(headPitch) {
            headPitch.pitchDeg.takeIf { headPitch.sampleCount > 0 && android.os.SystemClock.elapsedRealtime() - imuAt <= 300 }
        }
    override suspend fun gimbalRecenter() = send { LunaControl.gimbal(2) }
    override suspend fun gimbalFlip() = send { LunaControl.gimbal(3) }
    /** Official ROI centred on the tap, kept inside the frame. */
    override suspend fun tapFocus(x: Double, y: Double) = send {
        val w = LunaControl.FOCUS_WIDTH
        val h = LunaControl.FOCUS_HEIGHT
        LunaControl.tapFocus((x - w / 2).coerceIn(0.0, 1 - w), (y - h / 2).coerceIn(0.0, 1 - h), w, h, functionMode)
    }
    override suspend fun startTracking(x: Double, y: Double, width: Double, height: Double) =
        send { LunaControl.openTracking(x.coerceIn(0.0, 1.0), y.coerceIn(0.0, 1.0), width.coerceIn(0.0, 1.0), height.coerceIn(0.0, 1.0)) }
    override suspend fun stopTracking() = send { LunaControl.cancelTracking }
    override suspend fun startRecording() = send { LunaControl.startCapture(mode) }
    override suspend fun stopRecording() = send { LunaControl.stopCapture(mode) }
    override suspend fun takePhoto() = send { LunaControl.takePicture() }
    override suspend fun setExposure(iso: Int?, shutterSeconds: Double?) = send {
        val isoValue = iso?.toLong()
        LunaControl.videoExposure(LunaControl.exposureProgram(isoValue, shutterSeconds), isoValue, shutterSeconds, functionMode)
    }
    override suspend fun setExposureBias(thirds: Int) = send { LunaControl.exposureBias(thirds / 3.0, functionMode) }
    override suspend fun setWhiteBalance(kelvin: Int?) =
        send { kelvin?.let { LunaControl.whiteBalanceKelvin(it.toLong(), functionMode) } ?: LunaControl.whiteBalanceAuto(functionMode) }
    override suspend fun setColorProfile(profile: CameraColorProfile) = with(LunaReadout) { send { LunaControl.colorMode(colors.key(profile), functionMode) } }
    override suspend fun setRecordFormat(id: Long) = send { LunaControl.recordResolution(id, functionMode) }
    override suspend fun setShootingMode(mode: CameraShootingMode): Boolean {
        val luna = with(LunaReadout) { shootingModes.key(mode) }
        this.mode = luna
        val ok = send { luna.request() }
        if (ok) scope.launch { refreshStatus() }
        return ok
    }
    override suspend fun setGimbalMode(mode: CameraGimbalMode) = with(LunaReadout) { send { LunaControl.gimbalMode(gimbalModes.key(mode), functionMode) } }
    override suspend fun setGimbalSpeed(speed: CameraGimbalSpeed) = with(LunaReadout) { send { LunaControl.gimbalFollowSpeed(gimbalSpeeds.key(speed), functionMode) } }
    override suspend fun setFocusMode(mode: CameraFocusMode) = with(LunaReadout) { send { LunaControl.afMode(focusModes.key(mode), functionMode) } }
    override suspend fun setFaceMetering(on: Boolean) = send { LunaControl.faceMetering(on, functionMode) }

    // Media: cmd 13/38 list, cmd 11 thumbnail, cmd 12 delete; files over HTTP on 192.168.42.1.
    private suspend fun media(request: LunaControl.Request): ByteArray {
        val channel = checkNotNull(tcp) { "Connect the camera to browse clips." }
        check(_phase.value == ConnectionPhase.LIVE) { "Connect the camera to browse clips." }
        return channel.request(request.code, request.body)
    }
    override suspend fun listMedia(): List<CameraMediaItem> {
        runCatching { media(LunaControl.accessCameraFileState(LunaControl.ALBUM_ACCESS_STATE)) }
        val uris = LunaMediaFile.list(media(LunaControl.fileList())).first
        val infos = runCatching { LunaMediaFile.infoList(media(LunaControl.fileInfoList())) }.getOrDefault(emptyList()).associateBy { it.uri }
        return uris.map { infos[it] ?: LunaMediaFile(it) }.filterNot { it.isProxy }.map(LunaReadout::mediaItem)
    }
    override suspend fun thumbnailJpeg(path: String): ByteArray {
        val thumbnail = LunaThumbnail.parse(media(LunaControl.fileExtra(path, extraType = 2)))
        return withContext(Dispatchers.Default) {
            val bitmap = android.graphics.Bitmap.createBitmap(thumbnail.argb(), thumbnail.width, thumbnail.height, android.graphics.Bitmap.Config.ARGB_8888)
            java.io.ByteArrayOutputStream().also { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, it); bitmap.recycle() }.toByteArray()
        }
    }
    override suspend fun deleteMedia(path: String) { media(LunaControl.deleteFiles(path)) }
    override suspend fun pauseLive() { livePaused = true; runCatching { media(LunaControl.stopLive) } }
    override suspend fun resumeLive() {
        runCatching { media(LunaControl.stopLive) }
        lastVideoAt.set(android.os.SystemClock.elapsedRealtime())
        livePaused = false
        runCatching { media(LunaControl.accessCameraFileState(LunaControl.SHOOTING_VIEW_ACCESS_STATE)) }
        runCatching { media(LunaControl.startLive) }
    }
}
