package com.opencapture.openpocketcine.media

import com.opencapture.monitorui.MonitorConfirmPopup
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.media.MediaAssetID
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import com.opencapture.monitorui.monitorScrollFade
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.openpocketcine.panelGlass
import kotlinx.coroutines.launch
import com.opencapture.opencine.vocabulary.MediaLibraryTab
import com.opencapture.opencine.vocabulary.MediaLibrarySort
import com.opencapture.opencine.vocabulary.MediaLibraryQuery
import com.opencapture.opencine.vocabulary.MediaKind
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.cameracontrols.MediaThumbnailSize
import com.opencapture.opencine.cameracontrols.MediaLibraryCopy
import com.opencapture.opencine.cameracontrols.MediaClipPresentation
import com.opencapture.opencine.cameracontrols.MediaBrowserLayout
import com.opencapture.opencine.cameracontrols.MediaSelectionTray
import com.opencapture.opencine.cameracontrols.MediaScrollablePlaceholder
import com.opencapture.opencine.cameracontrols.MediaListingState
import com.opencapture.opencine.cameracontrols.MediaFilterPopup
import com.opencapture.opencine.cameracontrols.MediaEmptyState
import com.opencapture.opencine.cameracontrols.MediaCategoryTab
import com.opencapture.opencine.cameracontrols.MediaCategoryStrip
import com.opencapture.opencine.cameracontrols.MediaCatalogHeaderRow
import com.opencapture.opencine.cameracontrols.MediaCatalogDisplayControls
import com.opencapture.opencine.cameracontrols.MediaCacheBar
import com.opencapture.opencine.cameracontrols.LocalMediaBackdropGlass

internal fun mediaColorOptions(
    colors: Iterable<String?>,
    profile: com.opencapture.openpocketcine.session.CameraProfile,
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
    val scope = rememberCoroutineScope()
    androidx.compose.runtime.LaunchedEffect(library) { library.begin(); model.session.beginMediaBrowse() }
    // The outer shell owns retirement. Composition/rotation/player covers borrow this model.
    val category = MediaLibraryTab.valueOf(state.category.name)
    val layout = MediaBrowserLayout.valueOf(state.layout.name)
    val thumbnailSize = MediaThumbnailSize.valueOf(state.thumbnailSize.name)
    val sortOrder = MediaLibrarySort.valueOf(state.sort.name)
    var filterOpen by remember { mutableStateOf(false) }
    val formatFilters = state.formats
    val resolutionFilters = state.resolutions
    val dateStartKey = state.dateStart
    val dateEndKey = state.dateEnd
    val colorFilters = state.colors.mapNotNull(String::toIntOrNull).toSet()
    var playing by remember { mutableStateOf<MediaFile?>(null) }
    var viewingPhoto by remember { mutableStateOf<MediaFile?>(null) }
    val activity = LocalActivity.current as? com.opencapture.openpocketcine.MainActivity
    val fullscreenPlayback = playing != null || viewingPhoto != null
    DisposableEffect(activity, fullscreenPlayback) {
        activity?.playbackHidesSystemNavigation = fullscreenPlayback
        activity?.updateSystemBars()
        onDispose {
            activity?.playbackHidesSystemNavigation = false
            activity?.updateSystemBars()
        }
    }
    val isSelecting = state.selecting
    val selectedIDs = state.selectedIDs.map { it.rawValue }.toSet()
    var deliveryFiles by remember { mutableStateOf<List<MediaFile>?>(null) }
    var confirmBatchDelete by remember { mutableStateOf(false) }

    val filterSource = library.records(state.category).map { it.payload.file }
    val formatOptions = filterSource.map { it.fileExtension }.filter { it.isNotEmpty() }.toSet().sorted()
    val resolutionOptions = filterSource.mapNotNull { it.resolution }.filter { it.isNotEmpty() }.toSet().sorted()
    val colorOptions = mediaColorOptions(
        library.records(state.category).map { it.facts.color }, model.session.profile)
    val hasDates = filterSource.any { it.dateKey.isNotEmpty() }
    val displayedRecords = library.displayedRecords
    val displayed = displayedRecords.map { it.payload.file.copy(isStarred = it.favorite) }
    val displayedVideos = displayed.filter { it.kind == MediaKind.VIDEO }
    val selectedFiles = library.selectedRecords.map { it.payload.file }
    val activeFilterCount = state.activeFilterCount
    val headerCount =
        when {
            state.fetching && state.fetchedCount == 0 -> "Scanning…"
            state.fetching -> "Listing… ${state.fetchedCount} found"
            else -> {
                val n = displayed.size
                "$n item${if (n == 1) "" else "s"}"
            }
        }
    val headerTitle =
        when (category) {
            MediaLibraryTab.ALL -> "All clips"
            MediaLibraryTab.VIDEOS -> "Videos"
            MediaLibraryTab.PHOTOS -> "Photos"
            MediaLibraryTab.FAVORITES -> "Favorites"
        }
    val emptySubtitle =
        when {
            !isLive ->
                if (state.records.isEmpty()) MediaLibraryCopy.DISCONNECTED
                else MediaLibraryCopy.DISCONNECTED_EMPTY_CACHE
            activeFilterCount > 0 -> MediaLibraryCopy.FILTER_EMPTY
            category == MediaLibraryTab.FAVORITES -> MediaLibraryCopy.EMPTY_FAVORITES
            category == MediaLibraryTab.VIDEOS -> MediaLibraryCopy.EMPTY_VIDEOS
            category == MediaLibraryTab.PHOTOS -> MediaLibraryCopy.EMPTY_PHOTOS
            else -> MediaLibraryCopy.EMPTY_ALL
        }

    fun open(file: MediaFile) {
        if (isSelecting) {
            controller.record(file)?.let { library.select(state.selectedIDs.toggle(it.asset.id)) }
            return
        }
        if (!isLive && !controller.isAvailableOffline(file)) return
        if (file.kind == MediaKind.PHOTO) viewingPhoto = file else playing = file
    }

    fun exitSelection() {
        library.clearSelection()
        confirmBatchDelete = false
    }

    fun dismiss() {
        library.close(); model.session.endMediaBrowse()
        onClose()
    }

    BackHandler {
        when {
            deliveryFiles != null -> deliveryFiles = null
            confirmBatchDelete -> confirmBatchDelete = false
            playing != null -> playing = null
            viewingPhoto != null -> viewingPhoto = null
            filterOpen -> filterOpen = false
            isSelecting -> exitSelection()
            else -> dismiss()
        }
    }

    CompositionLocalProvider(LocalMonitorGlass provides null, LocalMediaBackdropGlass provides false) {
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {},
            ),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val portrait = maxHeight > maxWidth
            com.opencapture.monitorui.MonitorPageScaffold(
                modifier = Modifier.statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp),
                navigationWidth = 206f,
                heading = {
                    com.opencapture.monitorui.MonitorPageHeading(
                        "Media", model.session.connectedCamera?.name ?: "OpenInstaCine")
                },
                navigation = { compact ->
                    Column(
                        if (compact) Modifier.fillMaxWidth() else Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (compact) {
                            MediaCategoryStrip(category) { library.filter(category = MonitorMediaCategoryFilter.valueOf(it.name)) }
                        } else {
                            val railScroll = rememberScrollState()
                            Column(Modifier.weight(1f).monitorScrollFade(railScroll).verticalScroll(railScroll)) {
                                Column(Modifier.fillMaxWidth().monitorTabStrip()) {
                                    MediaLibraryTab.entries.forEach { tab ->
                                        MediaCategoryTab(tab, active = tab == category, fill = true) { library.filter(category = MonitorMediaCategoryFilter.valueOf(tab.name)) }
                                    }
                                }
                            }
                            MediaCatalogDisplayControls(
                                list = layout == MediaBrowserLayout.LIST,
                                thumbnailSize = thumbnailSize,
                                onList = { library.display(layout = if (it) com.opencapture.monitorui.MonitorMediaLayout.LIST else com.opencapture.monitorui.MonitorMediaLayout.GRID) },
                                onThumbnailSize = { library.display(thumbnailSize = com.opencapture.monitorui.MonitorThumbnailSize.valueOf(it.name)) },
                            )
                        }
                    }
                },
            ) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MediaCatalogHeaderRow(
                            headerTitle = headerTitle, headerCount = headerCount,
                            fetchInProgress = state.fetching, isLive = isLive,
                            isSelecting = isSelecting,
                            sortOrder = sortOrder, filterOpen = filterOpen, activeFilterCount = activeFilterCount,
                            compact = portrait,
                            onFilter = { filterOpen = !filterOpen }, onSort = { library.display(sort = MonitorMediaSort.valueOf(sortOrder.next.name)) },
                        )
                        controller.downloadProgress.entries.firstOrNull()?.let { (path, progress) ->
                            val name = displayed.firstOrNull { it.path == path }?.filename ?: path.substringAfterLast('/')
                            MediaCacheBar(name, progress)
                        }
                        Box(Modifier.weight(1f).fillMaxWidth()) {
                            MediaGalleryPane(
                                displayed = displayed,
                                layout = layout,
                                thumbnailSize = thumbnailSize,
                                category = category,
                                sortOrder = sortOrder,
                                controller = controller,
                                isSelecting = isSelecting,
                                selectedIDs = selectedIDs,
                                emptySubtitle = emptySubtitle,
                                connected = isLive,
                                onOpen = ::open,
                                onSelectionChange = { nextSelecting, nextIds ->
                                    if (nextSelecting) filterOpen = false
                                    library.select(nextIds.map { MediaAssetID(it) }.toSet(), nextSelecting)
                                },
                            )
                        }
                    if (isSelecting) MediaSelectionTray(selectedFiles.size,
                        cacheEnabled = selectedFiles.any(controller::canCache),
                        deleteEnabled = selectedFiles.any(controller::canDelete),
                        onAll = { library.selectAll() }, onClear = ::exitSelection,
                        onCache = { scope.launch { library.selectedRecords.filter { controller.canCache(it.payload.file) }.forEach { runCatching { library.cacheOriginal(it.asset.id) } } } },
                        onStar = {
                            val makeFavorite = selectedFiles.any { !controller.isFavorite(it) }
                            selectedFiles.filter { controller.isFavorite(it) != makeFavorite }.forEach(controller::toggleFavorite)
                        },
                        onDelete = { confirmBatchDelete = true },
                        onShare = { if (selectedFiles.isNotEmpty()) deliveryFiles = selectedFiles },
                    )
                    if (portrait) {
                        MediaCatalogDisplayControls(
                            list = layout == MediaBrowserLayout.LIST,
                            thumbnailSize = thumbnailSize,
                            onList = { library.display(layout = if (it) com.opencapture.monitorui.MonitorMediaLayout.LIST else com.opencapture.monitorui.MonitorMediaLayout.GRID) },
                            onThumbnailSize = { library.display(thumbnailSize = com.opencapture.monitorui.MonitorThumbnailSize.valueOf(it.name)) },
                        )
                    }
                }
            }
        }

        if (filterOpen) {
            MediaFilterPopup(
                formatOptions = formatOptions,
                resolutionOptions = resolutionOptions,
                colorOptions = colorOptions,
                hasDates = hasDates,
                formatFilters = formatFilters,
                resolutionFilters = resolutionFilters,
                colorFilters = colorFilters,
                dateStartKey = dateStartKey,
                dateEndKey = dateEndKey,
                onToggleFormat = { library.filter(formats = state.formats.toggle(it)) },
                onToggleResolution = { library.filter(resolutions = state.resolutions.toggle(it)) },
                onToggleColor = { library.filter(colors = state.colors.toggle(it.toString())) },
                onDateStart = { next ->
                    library.filter(dateStart = next, dateEnd = if (next != null && dateEndKey != null && next > dateEndKey) next else dateEndKey)
                },
                onDateEnd = { next ->
                    library.filter(dateEnd = next, dateStart = if (next != null && dateStartKey != null && next < dateStartKey) next else dateStartKey)
                },
                onClear = {
                    library.resetFilters()
                },
                onClose = { filterOpen = false },
            )
        }

        playing?.let { file ->
            MediaPlayerScreen(
                files = displayedVideos,
                startingAt = file,
                controller = controller,
                model = model,
                onClose = { playing = null },
                onDeliver = { deliveryFiles = listOf(it) },
            )
        }
        viewingPhoto?.let { file ->
            MediaPhotoViewer(
                model = model,
                file = file,
                controller = controller,
                onClose = { viewingPhoto = null },
                onDeliver = { deliveryFiles = listOf(it) },
            )
        }

        MediaDeliveryHost(
            files = deliveryFiles,
            controller = controller,
            onDismissPopup = { deliveryFiles = null },
        )

        if (confirmBatchDelete) {
            MonitorConfirmPopup(
                title = "Delete ${selectedIDs.size} item${if (selectedIDs.size == 1) "" else "s"} from the camera?",
                confirmTitle = "Delete",
                onClickFeedback = LocalOperatorHaptics.current::selection,
                onDismiss = { confirmBatchDelete = false },
                onConfirm = {
                    confirmBatchDelete = false
                    val doomed = selectedFiles
                    scope.launch {
                        doomed.forEach { controller.delete(it) }
                        exitSelection()
                    }
                },
            )
        }
    }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun MediaGalleryPane(
    displayed: List<MediaFile>,
    layout: MediaBrowserLayout,
    thumbnailSize: MediaThumbnailSize,
    category: MediaLibraryTab,
    sortOrder: MediaLibrarySort,
    controller: LunaMediaPlaybackAdapter,
    isSelecting: Boolean,
    selectedIDs: Set<String>,
    emptySubtitle: String,
    connected: Boolean,
    onOpen: (MediaFile) -> Unit,
    onSelectionChange: (Boolean, Set<String>) -> Unit,
) {
    val listState = rememberLazyListState()
    val gridState = rememberLazyGridState()
    val library = controller.library
    val state by library.state.collectAsState()
    fun identity(file: MediaFile) = controller.record(file)!!.asset.id.rawValue
    val ids = displayed.map(::identity)
    val gallery: @Composable () -> Unit = {
        com.opencapture.monitorui.MonitorMediaSelectionHost(
            ids = ids,
            selecting = isSelecting,
            selected = selectedIDs,
            scroll = if (layout == MediaBrowserLayout.LIST) listState else gridState,
            onOpen = { id -> displayed.firstOrNull { identity(it) == id }?.let(onOpen) },
            onSelectionChange = onSelectionChange,
            sessionKey = "${category.name}/${layout.name}/${thumbnailSize.name}/${sortOrder.name}",
        ) { registry ->
        Box(Modifier.fillMaxSize()) {
            when {
                displayed.isEmpty() && state.fetching ->
                    MediaScrollablePlaceholder { MediaListingState(state.fetchedCount) }
                displayed.isEmpty() ->
                    MediaScrollablePlaceholder {
                        MediaEmptyState(state.fetching, state.note ?: emptySubtitle)
                    }
                layout == MediaBrowserLayout.LIST -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize().monitorScrollFade(listState),
                        state = listState,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 24.dp),
                    ) {
                        items(displayed, key = ::identity) { file ->
                            com.opencapture.monitorui.MonitorMediaHitTarget(registry, identity(file)) {
                                MediaClipListRow(
                                    file = file,
                                    controller = controller,
                                    onOpen = { onOpen(file) },
                                    isSelecting = isSelecting,
                                    isSelected = selectedIDs.contains(identity(file)),
                                    onBeginSelection = {
                                        if (!isSelecting) onSelectionChange(true, setOf(identity(file)))
                                    },
                                    onToggleSelection = {
                                        val next = if (selectedIDs.contains(identity(file))) selectedIDs - identity(file)
                                            else selectedIDs + identity(file)
                                        onSelectionChange(true, next)
                                    },
                                )
                            }
                        }
                    }
                }
                else -> {
                    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
                    val columns = com.opencapture.monitorui.monitorCatalogColumns(
                        com.opencapture.monitorui.MonitorThumbnailSize.valueOf(thumbnailSize.name),
                        minOf(configuration.screenWidthDp, configuration.screenHeightDp) >= 600,
                    )
                    com.opencapture.monitorui.MonitorCatalogGrid(
                        displayed, columns, key = ::identity, modifier = Modifier.fillMaxSize(),
                        state = gridState,
                    ) { file ->
                        com.opencapture.monitorui.MonitorMediaHitTarget(registry, identity(file)) {
                            MediaClipCell(
                                file, controller, onOpen = { onOpen(file) },
                                isSelecting = isSelecting, isSelected = selectedIDs.contains(identity(file)),
                                onBeginSelection = {
                                    if (!isSelecting) onSelectionChange(true, setOf(identity(file)))
                                },
                                onToggleSelection = {
                                    val next = if (selectedIDs.contains(identity(file))) selectedIDs - identity(file)
                                        else selectedIDs + identity(file)
                                    onSelectionChange(true, next)
                                },
                            )
                        }
                    }
                }
            }
        }
        }
    }
    if (connected) {
        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = state.fetching,
            onRefresh = { if (!state.fetching) library.refresh() },
            modifier = Modifier.fillMaxSize(),
        ) { gallery() }
    } else gallery()
}

/** iOS selection chip: 13dp glyph beside its label. */

private fun <T> Set<T>.toggle(value: T): Set<T> =
    if (contains(value)) this - value else this + value
