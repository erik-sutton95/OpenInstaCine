package com.opencapture.openinstacine.monitor.media

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.cameracontrols.*
import com.opencapture.opencine.media.MediaAssetKind
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaClipFormatting
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.LocalMonitorGlass
import com.opencapture.opencine.insta360.shell.ConnectionPhase

internal fun mediaColorOptions(
    colors: Iterable<String?>,
    profile: com.opencapture.openinstacine.monitor.session.CameraProfile,
): List<Pair<Int, String>> = colors.mapNotNull { it?.toIntOrNull() }.toSet().sorted().mapNotNull { mode ->
    val label = com.opencapture.opencine.vocabulary.CameraCommands.colorLabel(mode, profile = profile.labels)
    if (label == "\u2014") null else mode to label
}


@Composable
fun MediaLibraryScreen(model: AppModel, onClose: () -> Unit) {
    val controller = model.mediaPlayback
    val library = model.mediaLibrary
    val state by library.state.collectAsState()
    val phase by model.session.phaseFlow.collectAsState()
    val isLive = library.canRefresh && phase == ConnectionPhase.LIVE
    // The outer shell retires source IO. Rotation and native player covers borrow this model.
    var presented by remember(library) { mutableStateOf<MonitorMediaGalleryOpen<LunaMediaLibraryPayload>?>(null) }
    var deliveryFiles by remember(library) { mutableStateOf<List<MediaFile>?>(null) }
    var deliveryActive by remember(library) { mutableStateOf(false) }
    LaunchedEffect(state.lifetimeToken) { presented = null; deliveryFiles = null }
    val activity = LocalActivity.current as? com.opencapture.openinstacine.monitor.MainActivity
    DisposableEffect(activity, presented?.id) {
        activity?.playbackHidesSystemNavigation = presented != null
        activity?.updateSystemBars()
        onDispose { activity?.playbackHidesSystemNavigation = false; activity?.updateSystemBars() }
    }
    fun dismiss() { library.close(); model.session.endMediaBrowse(); onClose() }
    val operations = MonitorMediaGalleryOperations<LunaMediaLibraryPayload>(
        download = if (isLive && library.canTransfer) { { controller.download(it.payload.file) } } else null,
        delete = if (isLive && library.canDelete) { { controller.delete(it.payload.file); Unit } } else null,
        favorite = { controller.toggleFavorite(it.payload.file) },
    )
    val colors = mediaColorOptions(library.records(state.category).map { it.facts.color }, model.session.profile)
        .map { it.first.toString() to it.second }
    CompositionLocalProvider(LocalMonitorGlass provides null, LocalMediaBackdropGlass provides false) {
        Box(Modifier.fillMaxSize()) {
            MonitorOperatorCatalogScreen(library, model.session.connectedCamera?.name ?: "OpenInstaCine", isLive,
                operations = operations, colorChoices = colors,
                facts = { record ->
                    val file = record.payload.file.copy(isStarred = record.favorite)
                    MonitorMediaGalleryFileFacts(listOfNotNull(file.resolution, file.fileExtension.uppercase()).joinToString(" · "),
                        file.durationSeconds.takeIf { it > 0 }?.let(MediaClipFormatting::durationLabel),
                        controller.downloadProgress[file.path])
                }, begin = { library.begin(); model.session.beginMediaBrowse() }, refresh = library::refresh, close = ::dismiss,
                open = { presented = it }, share = { records, token ->
                    if (library.isCurrent(token)) deliveryFiles = records.map { record -> record.payload.file.copy(isStarred = record.favorite) }
                }, handlesBack = presented == null && deliveryFiles == null,
                thumbnail = { MediaCatalogPicture(it, controller) })
            presented?.takeIf { library.isCurrent(it.admission) }?.let { request ->
                val file = request.record.payload.file.copy(isStarred = request.record.favorite)
                if ((request.record.facts.presentationKind ?: request.record.asset.kind) == MediaAssetKind.PHOTO)
                    MediaPhotoViewer(model = model, file = file, controller = controller, coverPresented = deliveryFiles != null,
                        onClose = { if (presented?.id == request.id) presented = null },
                        onDeliver = { if (presented?.id == request.id && library.isCurrent(request.admission)) deliveryFiles = listOf(it) })
                else MediaPlayerScreen(files = request.playlist.map { it.payload.file.copy(isStarred = it.favorite) }, startingAt = file, controller = controller,
                    model = model, coverPresented = deliveryFiles != null || deliveryActive, onClose = { if (presented?.id == request.id) presented = null },
                    onDeliver = { if (presented?.id == request.id && library.isCurrent(request.admission)) deliveryFiles = listOf(it) })
            }
            MediaDeliveryHost(files = deliveryFiles, controller = controller, onDismissPopup = { deliveryFiles = null },
                onPresentationChange = { deliveryActive = it })
        }
    }
    BackHandler(enabled = deliveryFiles != null || presented != null) {
        if (deliveryFiles != null) deliveryFiles = null else presented = null
    }
}
