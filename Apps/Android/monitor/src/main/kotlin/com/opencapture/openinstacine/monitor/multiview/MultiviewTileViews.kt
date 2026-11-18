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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.viewinterop.AndroidView
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.opencine.appkit.MonitorInspectorPreviewClient
import com.opencapture.opencine.appkit.MultiviewNetworkSetup
import com.opencapture.opencine.appkit.MultiviewSettingsCategory
import com.opencapture.opencine.cameracontrols.LiveControlSheet
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.runtime.NativeGlesFeedSession
import com.opencapture.openinstacine.monitor.LiveViewScreen
import com.opencapture.openinstacine.monitor.feed.LiveFeed
import com.opencapture.openinstacine.monitor.pairing.INSTA_STATION_BRAND
import com.opencapture.openinstacine.monitor.pairing.StationNetworkStorage
import com.opencapture.openinstacine.monitor.pairing.cameraWifiStorage
import com.opencapture.openinstacine.monitor.pairing.rememberPermissionGate

/**
 * One tile's picture, as Pocket Android's `TileFeed`: decoder, then the GPU feed with the tile's
 * Auto LUT, then a TextureView sized for Fit (letterboxed to the picture) or Fill (cropped). A device
 * without the GPU feed shows the decoder's picture directly. The decoder drops its output when the
 * first picture size arrives and on every raster change; the tile hands the same surface back then,
 * so a tile mounted before its camera's first keyframe still shows the picture.
 */
@Composable
internal fun TileFeed(tile: MultiviewSession.Tile, fill: Boolean) {
    val context = LocalContext.current
    var gpuFailed by remember(tile) { mutableStateOf(false) }
    val feed = remember(tile) {
        LiveFeed.glesFeed(
            context, tile.scopeBus, tile.inspectorPreview,
            onDecoderSurface = { surface -> tile.attachSurface(surface) },
            onGpuFailed = { gpuFailed = true },
        )
    }
    val previewOwner = tile.previewOwner
    LaunchedEffect(feed, tile.plan, previewOwner) {
        feed.updatePlan(if (previewOwner == null) tile.plan else tile.plan.withPreviewOwner(previewOwner))
    }
    // Camera settings' preview borrows this feed's GL present tap, like Live View's inspector.
    LaunchedEffect(feed, previewOwner != null) {
        feed.configurePreviewSource(tile, ready = true, active = previewOwner != null)
    }
    DisposableEffect(feed) {
        val decoder = tile.session.decoder
        if (decoder.pictureWidth > 0 && decoder.pictureHeight > 0) feed.setSourceSize(decoder.pictureWidth, decoder.pictureHeight)
        decoder.onOutputSizeChanged = { width, height ->
            feed.setSourceSize(width, height)
            tile.pictureSizeChanged()
        }
        onDispose {
            decoder.onOutputSizeChanged = null
            tile.handedSurface?.let(tile::detachSurface)
            feed.close()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
        // Reading `hasPicture` recomposes once the coded raster is known.
        val ratio = tile.hasPicture.let { tile.session.decoder.pictureAspect.toFloat() }.takeIf { it > 0f } ?: (16f / 9f)
        val width: Dp = if (fill) maxOf(maxWidth, maxHeight * ratio) else minOf(maxWidth, maxHeight * ratio)
        val height: Dp = if (fill) maxOf(maxHeight, maxWidth / ratio) else minOf(maxHeight, maxWidth / ratio)
        key(gpuFailed) {
            AndroidView(
                factory = { viewContext -> tileTextureView(viewContext, tile, feed, gles = !gpuFailed) },
                modifier = Modifier.requiredSize(width, height),
            )
        }
    }
}

private fun tileTextureView(context: Context, tile: MultiviewSession.Tile, feed: NativeGlesFeedSession, gles: Boolean) =
    TextureView(context).apply {
        isOpaque = true
        surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            private var plain: Surface? = null

            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                if (gles) {
                    feed.attachDisplay(texture, width, height)
                } else {
                    val next = Surface(texture)
                    plain?.release()
                    plain = next
                    tile.attachSurface(next)
                }
            }

            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
                if (gles) feed.resize(width, height)
            }

            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                tile.handedSurface?.let(tile::detachSurface)
                if (gles) feed.detachDisplay()
                plain?.release()
                plain = null
                return true
            }

            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
        }
    }

/** The borrowed Live View over the stage; its grid icon, its menu and Back go back to the stage. */
@Composable
internal fun MultiviewBorrowedLiveView(tile: MultiviewSession.Tile, exit: () -> Unit) {
    val leave by rememberUpdatedState(exit)
    val borrowed = tile.liveModel
    if (borrowed == null) {
        // The loan ended elsewhere (the camera's link closed under Live View): back to the stage.
        LaunchedEffect(tile) { leave() }
        return
    }
    DisposableEffect(borrowed) {
        borrowed.multiviewExit = {
            borrowed.shell.close()
            leave()
        }
        onDispose {}
    }
    LiveViewScreen(borrowed)
}

/** Live View's sheet for a shared settings category (iOS `CaptureSheet(rawValue:)`); null for one this app has none for. */
internal val MultiviewSettingsCategory.liveSheet: LiveSheet?
    get() = when (this) {
        MultiviewSettingsCategory.ISO -> LiveSheet.ISO
        MultiviewSettingsCategory.SHUTTER -> LiveSheet.SHUTTER
        MultiviewSettingsCategory.EXPOSURE -> LiveSheet.EXPO
        MultiviewSettingsCategory.WB -> LiveSheet.WB
        MultiviewSettingsCategory.FOCUS -> LiveSheet.FOCUS
        MultiviewSettingsCategory.APERTURE -> LiveSheet.APERTURE
        MultiviewSettingsCategory.MODE -> LiveSheet.MODE
        MultiviewSettingsCategory.RESOLUTION -> LiveSheet.FORMAT
        MultiviewSettingsCategory.COLOR -> LiveSheet.COLOR
        MultiviewSettingsCategory.AUDIO -> LiveSheet.AUDIO
    }

/**
 * The settings popup's controls on one tile: Live View's native pickers over the tile's open editor
 * (the shared popup adds its status line and the editor's note under them).
 */
@Composable
internal fun MultiviewSettingsControls(
    tile: MultiviewSession.Tile,
    category: MultiviewSettingsCategory,
    locked: Boolean,
    maxHeight: Float,
    close: () -> Unit,
) {
    val controls = tile.controlsModel ?: return
    val sheet = category.liveSheet ?: return
    val status by controls.session.chromeStatus.collectAsState()
    // Changing camera, category, recording or mode retires any in-progress drum gesture.
    key(controls, category, status.isRecording, status.shootingMode) {
        LiveControlSheet(
            sheet, controls, status, locked = locked,
            onDismiss = close, maxHeightDp = maxHeight, portrait = false, showsHeader = false,
        )
    }
}

/**
 * The settings popup's preview: the tile's own GL present tap through its inspector pipeline (as
 * Live View's inspector), never a second surface on the tile's decoder.
 */
@Composable
internal fun MultiviewSettingsPreview(tile: MultiviewSession.Tile, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val client = remember(tile, context) {
        object : MonitorInspectorPreviewClient<ImageBitmap> {
            override fun open(owner: Any, playback: Boolean, plan: FeedEffectsRenderPlan, receive: (ImageBitmap?) -> Unit) {
                tile.inspectorPreview.open(owner, playback, context, plan) { receive(it?.asImageBitmap()) }
                tile.previewOwner = owner
            }

            override fun update(owner: Any, plan: FeedEffectsRenderPlan) {
                tile.inspectorPreview.update(owner, plan)
            }

            override fun close(owner: Any) {
                if (tile.previewOwner === owner) tile.previewOwner = null
                tile.inspectorPreview.close(owner)
            }
        }
    }
    com.opencapture.opencine.cameracontrols.MonitorOperatorInspectorImagePreview(
        com.opencapture.monitorui.MonitorAssistTool.LUT, null, client, tile.plan,
        tile, null, false, modifier, "${tile.camera?.name ?: "Camera"} preview",
        com.opencapture.opencine.cameracontrols.MonitorInspectorPreviewLayout.SOURCE,
    )
}

/**
 * OpenCine's network wizard with this app's values: the Wi-Fi name permission, saved setups, the
 * shared path, and the saved cameras' own Wi-Fi names (never offered as the shared network).
 */
@Composable
internal fun LunaMultiviewNetworkSetup(
    session: MultiviewSession,
    stations: StationNetworkStorage,
    lockedNetwork: StationNetwork?,
    cancel: () -> Unit,
    complete: () -> Unit,
) {
    val context = LocalContext.current
    val saved = remember { stations.load().map { StationNetwork(it.ssid, it.password, it.hotspot) } }
    val cameraSsids = remember(session.appModel) {
        savedCameraSsids(context, session.appModel?.savedCameras?.map { it.id }.orEmpty())
    }
    MultiviewNetworkSetup(
        coordinator = session.coordinator,
        brand = INSTA_STATION_BRAND,
        wifiNameAccess = rememberPermissionGate("wifi-name", DiscoveryPermissions.wifiName, DiscoveryPermissions.wifiNameRequest),
        savedNetworks = saved,
        currentSsid = session.path::currentSsid,
        lockedNetwork = lockedNetwork,
        cancel = cancel,
        complete = complete,
        cameraSsids = cameraSsids,
        sourceChosen = { hotspot -> session.path.hotspot = hotspot },
    )
}

/** The saved cameras' own access point names, as the credential store keeps them (no password read). */
internal fun savedCameraSsids(context: Context, cameraIds: List<String>): Set<String> {
    val preferences = context.applicationContext.getSharedPreferences(cameraWifiStorage.preferencesName, Context.MODE_PRIVATE)
    return cameraIds.mapNotNull { id ->
        preferences.getString(id + cameraWifiStorage.ssidKeySuffix, null)?.takeIf { it.isNotBlank() }
    }.toSet()
}
