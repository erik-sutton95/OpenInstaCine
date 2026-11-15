package com.opencapture.openinstacine.monitor.multiview

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.viewinterop.AndroidView
import com.opencapture.opencine.appkit.MultiviewCoordinator
import com.opencapture.opencine.appkit.MultiviewMember
import com.opencapture.opencine.appkit.MultiviewMemberChange
import com.opencapture.opencine.appkit.MultiviewNetworkSetup
import com.opencapture.opencine.appkit.MultiviewNetworkStorage
import com.opencapture.opencine.appkit.MultiviewScreenHost
import com.opencapture.opencine.appkit.MultiviewSettingsCategory
import com.opencapture.opencine.appkit.MultiviewTileReadings
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.core.PictureHealth
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.opencine.decoder.HevcDecoder
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.opencine.insta360.luna.LunaMemberLink
import com.opencapture.opencine.insta360.luna.LunaMultiview
import com.opencapture.opencine.insta360.luna.LunaNearbyScanner
import com.opencapture.opencine.insta360.luna.LunaStationCommissioner
import com.opencapture.opencine.insta360.luna.LunaStationNetwork
import com.opencapture.opencine.media.LivePipelineCadence
import com.opencapture.opencine.platform.SharedWiFiPath
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.openinstacine.monitor.diagnostics.DiagnosticCenter
import com.opencapture.openinstacine.monitor.pairing.INSTA_STATION_BRAND
import com.opencapture.openinstacine.monitor.pairing.StationNetworkStorage
import com.opencapture.openinstacine.monitor.pairing.rememberPermissionGate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * OpenInstaCine's Android Multiview: OpenCine's shared stage ([MultiviewCoordinator]) over Luna's
 * Multiview seams ([LunaMultiview.policy], [LunaStationCommissioner], [LunaMemberLink]), with this
 * session as the screen's host. Each tile has its own [LunaBackend] (on the app's one
 * [SharedWiFiPath]), its own decoder and its own member link. Live View borrowing, the settings
 * popup and Auto LUT are not offered here yet (the host's capability values say so, so the shared
 * screen hides them). Hardware-untested.
 *
 * @param makeBackend a new Luna connection (a tile's, a commission's or a return's).
 * @param discover the app's passive Luna discovery for the Add list.
 */
class MultiviewSession(
    context: Context,
    makeBackend: () -> LunaBackend,
    discover: () -> Flow<List<NearbyCamera>>,
    val path: SharedWiFiPath,
) : MultiviewScreenHost, AutoCloseable {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val stations = StationNetworkStorage(appContext)

    /** One stage slot: its connection, decoder and member link. */
    class Tile(val backend: LunaBackend, clock: () -> Long, scope: CoroutineScope) {
        val decoder = HevcDecoder(LivePipelineCadence(), errorJournal = DiagnosticCenter::logDecoderError)
        val link = LunaMemberLink(backend, clock)
        val member = MultiviewMember<NearbyCamera>()
        var aspect by mutableDoubleStateOf(16.0 / 9.0)
            private set

        init {
            decoder.onOutputSizeChanged = { width, height -> if (width > 0 && height > 0) aspect = width.toDouble() / height }
            scope.launch(Dispatchers.Default) {
                backend.frames.collect { frame ->
                    // Only the current connection's frames reach the tile (Luna stamps every frame).
                    if (frame.connectionGeneration == backend.frameConnectionGeneration) decoder.decode(frame.annexB)
                }
            }
        }
    }

    private val clock: () -> Long = { android.os.SystemClock.elapsedRealtime() }
    val tiles: List<Tile> = List(MultiviewQualificationPolicy.tileCount) { Tile(makeBackend(), clock, scope) }

    /** The app's record confirmation preference (Settings). */
    var recordConfirmation: () -> Boolean = { true }

    val coordinator = MultiviewCoordinator(
        links = tiles.map { it.link },
        members = tiles.map { it.member },
        policy = LunaMultiview.policy,
        commissioner = LunaStationCommissioner(makePort = makeBackend),
        scanner = LunaNearbyScanner(discover),
        hostPath = path,
        describe = LunaMultiview::record,
        journal = MultiviewStageStore.storage(appContext),
        networks = MultiviewNetworkStorage(
            password = { ssid, hotspot -> stations.load().firstOrNull { it.ssid == ssid && it.hotspot == hotspot }?.password },
            save = { stations.save(LunaStationNetwork(it.ssid, it.password, it.hotspot)) },
        ),
        scope = scope,
        budget = MultiviewQualificationPolicy.budget,
        probeWidth = 24,
        clock = clock,
    ).also { it.host = this }

    init {
        // No search or open of one member reaches a camera another member holds.
        tiles.forEachIndexed { slot, tile ->
            tile.backend.stationHostsInUse = {
                tiles.withIndex().mapNotNull { (other, it) -> if (other == slot) null else it.member.controlHost }.toSet()
            }
        }
    }

    override val confirmsRecord: Boolean get() = recordConfirmation()

    override fun memberChanged(slot: Int, change: MultiviewMemberChange) {
        if (change == MultiviewMemberChange.REMOVED) tiles[slot].decoder.reset()
    }

    override fun stageStopped() {
        tiles.forEach { it.decoder.reset() }
    }

    override fun log(line: String) {
        android.util.Log.i("Multiview", line)
    }

    override fun readings(slot: Int): MultiviewTileReadings? {
        val tile = tiles[slot]
        val camera = tile.member.camera ?: return null
        val live = tile.link.pictureHealth == PictureHealth.LIVE
        return MultiviewTileReadings(
            name = camera.name, model = camera.model, power = tile.link.session.snapshots.value.power,
            hasPicture = live, accessibilityValue = if (live) "Live" else "Reconnecting",
        )
    }

    @Composable
    override fun Picture(slot: Int, fill: Boolean) {
        TilePicture(tiles[slot], fill)
    }

    @Composable
    override fun SettingsPreview(slot: Int, modifier: Modifier) {}

    @Composable
    override fun SettingsControls(slot: Int, category: MultiviewSettingsCategory, locked: Boolean, maxHeight: Float, close: () -> Unit) {}

    @Composable
    override fun LiveView(slot: Int, exit: () -> Unit) {}

    @Composable
    override fun NetworkSetup(lockedNetwork: StationNetwork?, cancel: () -> Unit, complete: () -> Unit) {
        val saved = remember { stations.load().map { StationNetwork(it.ssid, it.password, it.hotspot) } }
        MultiviewNetworkSetup(
            coordinator = coordinator,
            brand = INSTA_STATION_BRAND,
            wifiNameAccess = rememberPermissionGate("wifi-name", DiscoveryPermissions.wifiName, DiscoveryPermissions.wifiNameRequest),
            savedNetworks = saved,
            currentSsid = path::currentSsid,
            lockedNetwork = lockedNetwork,
            cancel = cancel,
            complete = complete,
            sourceChosen = { hotspot -> path.hotspot = hotspot },
        )
    }

    /** Closes every member's connection and decoder (never a camera command). */
    override fun close() {
        coordinator.stop()
        tiles.forEach { it.backend.close(); it.decoder.onOutputSizeChanged = null; it.decoder.reset() }
        scope.cancel()
    }
}

/** The member decoder's picture on a TextureView, sized by its aspect: Fill crops, Fit letterboxes. */
@Composable
private fun TilePicture(tile: MultiviewSession.Tile, fill: Boolean) {
    val handed = remember(tile) { arrayOfNulls<Surface>(1) }
    DisposableEffect(tile) {
        onDispose {
            handed[0]?.let { tile.decoder.detachSurface(it); it.release() }
            handed[0] = null
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
        val ratio = tile.aspect.toFloat()
        val width: Dp = if (fill) maxOf(maxWidth, maxHeight * ratio) else maxWidth
        val height: Dp = if (fill) maxOf(maxHeight, maxWidth / ratio) else maxHeight
        AndroidView(
            factory = { context ->
                TextureView(context).apply {
                    isOpaque = true
                    surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                        override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                            handed[0] = Surface(texture).also(tile.decoder::attachSurface)
                        }

                        override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit

                        override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                            handed[0]?.let { tile.decoder.detachSurface(it); it.release() }
                            handed[0] = null
                            return true
                        }

                        override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
                    }
                }
            },
            modifier = Modifier.requiredSize(width, height),
        )
    }
}
