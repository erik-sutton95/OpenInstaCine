package com.opencapture.openinstacine.monitor.multiview

import android.content.Context
import android.view.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.opencapture.opencine.appkit.MultiviewCameraSettingsState
import com.opencapture.opencine.appkit.MultiviewCoordinator
import com.opencapture.opencine.appkit.MultiviewMember
import com.opencapture.opencine.appkit.MultiviewMemberChange
import com.opencapture.opencine.appkit.MultiviewNetworkStorage
import com.opencapture.opencine.appkit.MultiviewScreenHost
import com.opencapture.opencine.appkit.MultiviewSettingsCategory
import com.opencapture.opencine.appkit.MultiviewTileReadings
import com.opencapture.opencine.cameracontrols.MonitorFeedEffectsPlans
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.core.PictureHealth
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.opencine.insta360.luna.LunaMemberLink
import com.opencapture.opencine.insta360.luna.LunaMultiview
import com.opencapture.opencine.insta360.luna.LunaNearbyScanner
import com.opencapture.opencine.insta360.luna.LunaStationCommissioner
import com.opencapture.opencine.insta360.luna.LunaStationNetwork
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.media.HostShutterPresentation
import com.opencapture.opencine.multicam.EditorLease
import com.opencapture.opencine.platform.SharedWiFiPath
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.openinstacine.monitor.pairing.StationNetworkStorage
import com.opencapture.openinstacine.monitor.session.LunaCameraLUTProfile
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * OpenInstaCine's Android Multiview: OpenCine's shared stage ([MultiviewCoordinator]) over Luna's
 * Multiview seams ([LunaMultiview.policy], [LunaStationCommissioner], [LunaMemberLink]), with this
 * session as the screen's host, as iOS `MultiviewSession` and Pocket Android. Each tile has its own
 * connection (a [LunaBackend] on the app's one [SharedWiFiPath]), its own app session (decoder,
 * status and controls, without the monitor's own recovery) and its own member link. The host offers
 * everything Pocket's does: the GPU tile picture with its Auto LUT, Live View borrowed from a tile,
 * the camera settings popup under the stage's editor lease, and the tile readouts. Hardware-untested.
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

    /** One stage slot: its connection, app session, member link and picture. */
    class Tile(
        val index: Int,
        val backend: LunaBackend,
        private val app: Context,
        clock: () -> Long,
        private val scope: CoroutineScope,
    ) {
        /** The tile's picture, status and controls (iOS `Tile.session`): never the monitor's. */
        val session = PocketCameraSession(app, memberBackend = backend)
        /** The stage's link to the tile's camera (OpenCine `insta360-luna`). */
        val link = LunaMemberLink(
            backend, clock, conversion = MultiviewLut::conversion,
            preview = { MultiviewLut.previewProfile(it) },
        )
        val member = MultiviewMember<NearbyCamera>()
        val camera: NearbyCamera? get() = member.camera
        val scopeBus = com.opencapture.opencine.runtime.ScopeSampleBus()
        val inspectorPreview = com.opencapture.opencine.runtime.InspectorPreviewPipeline(
            scopeBus, { com.opencapture.opencine.runtime.NativeGlBackend.create(it) }, "OpcTileInspector")
        internal val feedEffectsPlans = MonitorFeedEffectsPlans(SwiftCore)

        /** A borrowed Live View, while one is open. */
        var liveModel by mutableStateOf<AppModel?>(null)
        /** A settings editor, while one is open, and the stage's lease it edits under. */
        var controlsModel by mutableStateOf<AppModel?>(null)
            internal set
        internal var editorLease: EditorLease? = null
        /** The settings popup's preview owner; the tile's own GL present tap feeds it while set. */
        internal var previewOwner by mutableStateOf<Any?>(null)
        /** The tile's Auto LUT plan (the camera's conversion only, no assists). */
        internal var plan by mutableStateOf(FeedEffectsRenderPlan.IDENTITY)
        /** The tile's camera status, followed for its readouts and Auto LUT. */
        var settings by mutableStateOf(CameraStatus())
            private set
        /** Compose state the stage reads (the link's own values are plain fields). */
        var hasPicture by mutableStateOf(false)
            private set
        /** The member's battery, followed so the stage recomposes when it changes. */
        var power by mutableStateOf<PowerStatus?>(null)
            private set
        /** The tile's TextureView currently shows the decoder's picture. */
        internal var surfaceMounted = false
        /** The decoder surface the tile's picture handed it, re-attached when the picture size arrives. */
        internal var handedSurface: Surface? = null

        init {
            session.control.bind(link.session)
            configureSession()
            scope.launch {
                session.status.collect { status ->
                    val colorChanged = status.colorMode != settings.colorMode
                    settings = status
                    // Pocket re-grades when the camera reports its color (the same rule as Live View).
                    if (colorChanged && liveModel == null) updateLUT()
                }
            }
            scope.launch {
                link.session.snapshots.map { it.power }.distinctUntilChanged().collect { power = it }
            }
            scope.launch {
                while (isActive) {
                    hasPicture = link.pictureHealth == PictureHealth.LIVE
                    delay(500)
                }
            }
        }

        var lutEnabled: Boolean
            get() = member.lutEnabled
            set(value) { member.lutEnabled = value }

        /** The member's session as the monitor's own: the operator's shutter presentation. */
        fun configureSession() {
            link.lunaSession.configureShutter(
                if (OperatorPrefs.shutterUsesAngle(app)) HostShutterPresentation.EMULATED_ANGLE
                else HostShutterPresentation.CAMERA_VALUE,
            )
        }

        /** Applies the member's Auto LUT choice: the bundled conversion for what the picture carries. */
        fun updateLUT() {
            plan = feedEffectsPlans.multiviewAutoLut(
                app, lutEnabled, MultiviewLut.previewColorMode(settings), LunaCameraLUTProfile.value,
            ).first
        }

        /** Ends the tile's editor and its lease (its controls stay bound to the member's session). */
        fun retireControls() {
            controlsModel?.let { model ->
                model.multiviewExit = null
                model.close()
            }
            controlsModel = null
            editorLease = null
        }

        fun attachSurface(surface: Surface) {
            handedSurface = surface
            session.decoder.attachSurface(surface)
            surfaceMounted = true
        }

        fun detachSurface(surface: Surface) {
            session.decoder.detachSurface(surface)
            if (handedSurface === surface) handedSurface = null
            if (liveModel == null) surfaceMounted = false
        }

        /**
         * The decoder drops its output surface when the first picture size arrives (and on every
         * raster change) and waits for the host to hand one back: the tile hands back the one it
         * holds, so a tile mounted before its camera's first keyframe still shows its picture.
         */
        fun pictureSizeChanged() {
            handedSurface?.let(session.decoder::attachSurface)
        }

        internal fun close() {
            retireControls()
            liveModel?.let { it.multiviewExit = null; it.close() }
            liveModel = null
            session.close()
            backend.close()
            feedEffectsPlans.close()
            inspectorPreview.close()
        }
    }

    private val clock: () -> Long = { android.os.SystemClock.elapsedRealtime() }
    val tiles: List<Tile> = List(MultiviewQualificationPolicy.tileCount) { Tile(it, makeBackend(), appContext, clock, scope) }

    /** The app's model: the record confirmation preference and the saved cameras' Wi-Fi names. */
    var appModel: AppModel? = null

    /** The app's record confirmation preference (Settings). */
    var recordConfirmation: () -> Boolean = { appModel?.recordConfirmationEnabled ?: true }

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
        tiles.forEachIndexed { slot, tile ->
            // No search or open of one member reaches a camera another member holds.
            tile.backend.stationHostsInUse = {
                tiles.withIndex().mapNotNull { (other, it) -> if (other == slot) null else it.member.controlHost }.toSet()
            }
            // Pocket's per-write admission: Live View's borrowed monitor writes as the monitor does;
            // otherwise only the open editor, while its lease and the stage admit the change.
            tile.session.multiviewControlAdmission = {
                tile.liveModel != null || (tile.controlsModel != null &&
                    tile.editorLease?.let { coordinator.editorAdmits(it, slot) } == true)
            }
        }
    }

    // --- MultiviewHost --------------------------------------------------------------------------

    override val confirmsRecord: Boolean get() = recordConfirmation()
    override val editsCameraSettings: Boolean get() = true
    override val appliesAutoLUT: Boolean get() = true

    override fun lutChanged(slot: Int) = tiles[slot].updateLUT()

    override fun readings(slot: Int): MultiviewTileReadings? {
        val tile = tiles[slot]
        val camera = tile.camera ?: return null
        return MultiviewTileValues.readings(camera, tile.settings, tile.link.session.snapshots.value, tile.hasPicture)
    }

    /**
     * Lends the tile's own session (picture, status, controls) to a Live View model whose shell
     * borrows it as the monitor (Pocket `borrowMonitor`); the stage keeps the link and its repair.
     */
    override fun openLiveView(slot: Int): Boolean {
        val tile = tiles[slot]
        val camera = tile.camera ?: return false
        val model = AppModel(appContext, borrowing = tile.session)
        model.prepareStartup()
        model.setBorrowedLut(tile.lutEnabled)
        tile.liveModel = model
        model.borrowMonitor(camera, tile.link.session) { releaseLiveView(tile) }
        return true
    }

    private fun releaseLiveView(tile: Tile) {
        val model = tile.liveModel ?: return
        tile.liveModel = null
        tile.lutEnabled = model.borrowedLutEnabled()
        model.multiviewExit = null
        model.close()
        // The borrowed monitor's shell unbound the shared controls when it closed.
        tile.session.control.bind(tile.link.session)
        tile.configureSession()
        tile.updateLUT()
    }

    override fun closeLiveView() {
        for (tile in tiles) releaseLiveView(tile)
    }

    /**
     * Opens a settings editor over the tile's own controls under the stage's editor lease (Pocket:
     * a replaced link or camera, a lost authority or the next editor retires it).
     */
    override fun openCameraSettings(slot: Int) {
        // Opening the lease closes every other editor first.
        val lease = coordinator.openEditorLease(slot) ?: return
        val tile = tiles[slot]
        if (tile.camera == null || !coordinator.controlsAvailable(slot)) return
        tile.controlsModel = AppModel(appContext, borrowing = tile.session)
        tile.editorLease = lease
    }

    override fun cameraSettings(slot: Int): MultiviewCameraSettingsState? {
        val tile = tiles[slot]
        val model = tile.controlsModel ?: return null
        val status = tile.settings
        return MultiviewCameraSettingsState(
            categories = MultiviewSettingsCategory.offered(
                focus = model.session.supportsFocusMode, aperture = false,
                photo = status.isPhoto, audio = false,
            ),
            recording = status.isRecording,
            note = model.session.controlNote.value,
        )
    }

    /** The tile's own link is up and no Live View borrows it. */
    override fun admitsControls(slot: Int): Boolean {
        val tile = tiles[slot]
        return tile.backend.phase.value == com.opencapture.opencine.insta360.shell.ConnectionPhase.LIVE && tile.liveModel == null
    }

    override fun closeEditors() {
        for (tile in tiles) tile.retireControls()
    }

    override fun memberChanged(slot: Int, change: MultiviewMemberChange) {
        val tile = tiles[slot]
        when (change) {
            MultiviewMemberChange.CAMERA -> {
                tile.retireControls()
                tile.configureSession()
            }
            MultiviewMemberChange.CONTROL -> tile.retireControls()
            MultiviewMemberChange.REMOVED -> {
                tile.retireControls()
                tile.session.decoder.reset()
                tile.updateLUT()
            }
        }
    }

    override fun stageStopped() {
        tiles.forEach { it.session.decoder.reset() }
    }

    /** A tile repairs only while a surface shows its picture (Pocket). */
    override fun showsPicture(slot: Int): Boolean = tiles[slot].surfaceMounted || tiles[slot].liveModel != null

    override fun log(line: String) {
        android.util.Log.i("Multiview", line)
    }

    // --- MultiviewScreenHost --------------------------------------------------------------------

    @Composable
    override fun Picture(slot: Int, fill: Boolean) {
        val tile = tiles[slot]
        if (tile.liveModel == null) TileFeed(tile, fill)
    }

    @Composable
    override fun SettingsPreview(slot: Int, modifier: Modifier) = MultiviewSettingsPreview(tiles[slot], modifier)

    @Composable
    override fun SettingsControls(slot: Int, category: MultiviewSettingsCategory, locked: Boolean, maxHeight: Float, close: () -> Unit) =
        MultiviewSettingsControls(tiles[slot], category, locked, maxHeight, close)

    @Composable
    override fun LiveView(slot: Int, exit: () -> Unit) = MultiviewBorrowedLiveView(tiles[slot], exit)

    @Composable
    override fun NetworkSetup(lockedNetwork: StationNetwork?, cancel: () -> Unit, complete: () -> Unit) =
        LunaMultiviewNetworkSetup(this, stations, lockedNetwork, cancel, complete)

    /**
     * Closes every member's connection and session (never a camera command) and lets go of the
     * shared Wi-Fi the stage joined, as Pocket's `path.release()`: the monitor is disconnected while
     * the stage is open, so nothing else holds it.
     */
    override fun close() {
        coordinator.stop()
        tiles.forEach { it.close() }
        path.release()
        scope.cancel()
    }
}
