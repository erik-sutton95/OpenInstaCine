package com.opencapture.openinstacine.monitor.media

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.*
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.cameracontrols.*
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
    // Hoisted so the staged SIMULATED review can open its first clip (iOS `MediaLibraryStub`
    // `opensFirstClip`); the screen's own host is this same remembered construction.
    val mediaHost = remember(library) { com.opencapture.opencine.appkit.MonitorOperatorMediaHost(library) }
    val state by library.state.collectAsState()
    val phase by model.session.phaseFlow.collectAsState()
    val isLive = library.canRefresh && phase == ConnectionPhase.LIVE
    // The outer shell retires source IO. Rotation and native player covers borrow this model.
    var deliveryFiles by remember(library) { mutableStateOf<List<MediaFile>?>(null) }
    var deliveryActive by remember(library) { mutableStateOf(false) }
    LaunchedEffect(state.lifetimeToken) { deliveryFiles = null }
    val activity = LocalActivity.current as? com.opencapture.openinstacine.monitor.MainActivity
    fun dismiss() { library.close(); model.session.endMediaBrowse(); onClose() }
    fun file(record: MonitorMediaRecord<LunaMediaLibraryPayload>) = record.payload.file.copy(isStarred = record.favorite)
    val operations = MonitorMediaGalleryOperations<LunaMediaLibraryPayload>(
        // The library throws a failed clip, so the shared gallery says "Could not cache that clip."
        // and goes on to the next; delivery keeps its own quiet acquire and counts what is missing.
        download = if (isLive && library.canTransfer) { { library.cacheOriginal(it.asset.id); Unit } } else null,
        delete = if (isLive && library.canDelete) { { controller.delete(it.payload.file); Unit } } else null,
        favorite = { controller.toggleFavorite(it.payload.file) },
    )
    val colors = mediaColorOptions(library.records(state.category).map { it.facts.color }, model.session.profile)
        .map { it.first.toString() to it.second }
    // `ReviewLaunch(screen: .playback)`: open the first staged clip once, as a tap would. The
    // gallery's own begin retires the lifetime it starts with, so the open waits for the browsing
    // lifetime and retries on every relist until the presentation holds.
    if (model.reviewLaunch?.screen == com.opencapture.monitorui.ReviewLaunch.Screen.PLAYBACK) {
        var stagedClipOpened by remember { mutableStateOf(false) }
        LaunchedEffect(mediaHost, state.lifetimeToken, library.displayedRecords.firstOrNull()?.asset?.id) {
            if (stagedClipOpened || !state.browsing) return@LaunchedEffect
            val records = library.displayedRecords
            val first = records.firstOrNull() ?: return@LaunchedEffect
            if (mediaHost.open(com.opencapture.opencine.appkit.MonitorMediaGalleryOpen(first, records,
                library.actionToken))) stagedClipOpened = true
        }
    }
    CompositionLocalProvider(LocalMonitorGlass provides null, LocalMediaBackdropGlass provides false) {
        MonitorOperatorMediaScreen(library, model.session.connectedCamera?.name ?: "OpenInstaCine", isLive,
            operations = operations, colorChoices = colors,
            facts = { record ->
                val file = file(record)
                MonitorMediaGalleryFileFacts(listOfNotNull(file.resolution, file.fileExtension.uppercase()).joinToString(" · "),
                    file.durationSeconds.takeIf { it > 0 }?.let(MediaClipFormatting::durationLabel),
                    controller.downloadProgress[file.path])
            }, begin = { library.begin(); model.session.beginMediaBrowse() }, refresh = library::refresh, close = ::dismiss,
            thumbnail = { MonitorMediaCatalogPicture(it, it.record.payload.file, controller) },
            player = { page ->
                MediaPlayerScreen(opening = page.request, files = page.request.playlist.map(::file), startingAt = file(page.request.record),
                    controller = controller, model = model, coverPresented = page.coverPresented || deliveryActive,
                    onClose = page::close, onDeliver = { if (page.isCurrent) deliveryFiles = listOf(it) })
            },
            photo = { page ->
                MediaPhotoViewer(opening = page.request, model = model, file = file(page.request.record), controller = controller,
                    coverPresented = page.coverPresented, onClose = page::close,
                    onDeliver = { if (page.isCurrent) deliveryFiles = listOf(it) })
            },
            delivery = MonitorOperatorMediaDelivery(deliveryFiles != null, share = { records, token ->
                if (library.isCurrent(token)) deliveryFiles = records.map(::file)
            }, dismiss = { deliveryFiles = null }),
            presentationChanged = { shown -> activity?.playbackHidesSystemNavigation = shown; activity?.updateSystemBars() },
            host = mediaHost,
            overlays = {
                MediaDeliveryHost(files = deliveryFiles, controller = controller, onDismissPopup = { deliveryFiles = null },
                    onPresentationChange = { deliveryActive = it })
            })
    }
}
