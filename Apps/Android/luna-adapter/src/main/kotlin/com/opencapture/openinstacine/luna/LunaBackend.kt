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

/** Luna transport only. No Compose, camera-setting writes, packet logs, or saved passwords. */
@SuppressLint("MissingPermission")
class LunaBackend(context: Context) : CameraBackend {
    private val context = context.applicationContext
    private val bluetooth = context.getSystemService(BluetoothManager::class.java)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val preferences = context.getSharedPreferences("openinstacine.client-identity", Context.MODE_PRIVATE)
    private val clientIdentity: String = preferences.getString("authorization-id", null) ?: UUID.randomUUID().toString().uppercase().also { preferences.edit().putString("authorization-id", it).apply() }
    override val capabilities = setOf(CameraCapability.LIVE_VIDEO)
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
    private var connectJob: Job? = null
    private var scanActive = false
    @Volatile private var socket: Socket? = null
    @Volatile private var tcp: LunaChannel? = null
    private var gatt: LunaGatt? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wasInactive = false
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
        _phase.value = ConnectionPhase.OPENING_DATALINK
        val cameraSocket = withContext(Dispatchers.IO) {
            network.socketFactory.createSocket().also { socket = it; it.tcpNoDelay = true; it.soTimeout = 10_000; it.connect(InetSocketAddress("192.168.42.1", 6666), 8_000) }
        }
        val lastVideoAt = java.util.concurrent.atomic.AtomicLong(android.os.SystemClock.elapsedRealtime())
        val channel = LunaChannel(send = { bytes -> withContext(Dispatchers.IO) { cameraSocket.getOutputStream().write(bytes); cameraSocket.getOutputStream().flush() } }, video = { bytes, tick -> lastVideoAt.set(android.os.SystemClock.elapsedRealtime()); video.tryEmit(EncodedVideoFrame(bytes, tick)) })
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
            channel.request(1, LunaWire.liveBody)
            lastVideoAt.set(android.os.SystemClock.elapsedRealtime())
            watchdog = launch { while (isActive) { delay(2_000); if (android.os.SystemClock.elapsedRealtime() - lastVideoAt.get() > 10_000) { channel.fail(IllegalStateException("No live video received")); break } } }
            throw channel.failure.await()
        } finally {
            withContext(NonCancellable) { withTimeoutOrNull(1_500) { runCatching { channel.request(2) } } }
            watchdog?.cancel(); heartbeat?.cancel(); cameraSocket.close(); receiver.cancel(); channel.close(); tcp = null
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
}
