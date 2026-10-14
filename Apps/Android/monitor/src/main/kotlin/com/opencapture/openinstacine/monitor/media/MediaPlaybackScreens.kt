@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openinstacine.monitor.media

import com.opencapture.opencine.appkit.MonitorMediaGalleryOpen

import com.opencapture.monitorui.MonitorConfirmPopup
import com.opencapture.opencine.media3.Media3PlaybackOwner
import com.opencapture.monitorui.MonitorPlaybackScreen
import com.opencapture.monitorui.MonitorPlaybackPresentation
import com.opencapture.monitorui.MonitorPlaybackActions
import com.opencapture.monitorui.MonitorEditingCancellation
import com.opencapture.monitorui.detectMonitorPlaybackVideoGestures as detectPlaybackVideoGestures
import com.opencapture.monitorui.monitorPlaybackUnitPoint as unitPoint

import com.opencapture.opencine.media.MonitorConformPreview as ConformPreview
import com.opencapture.opencine.media.MonitorPlaybackLookTiming
import com.opencapture.opencine.appkit.MonitorMediaPlaybackModel

import com.opencapture.opencine.vocabulary.colorMode

import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.openinstacine.monitor.feed.rememberMonitorBackdropFeed
import android.graphics.Bitmap
import com.opencapture.opencine.appkit.MonitorBitmapDecoder
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.opencapture.monitorui.MonitorPlaybackLayout
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.GlassTier
import com.opencapture.openinstacine.monitor.LiveDesign
import com.opencapture.openinstacine.monitor.liveModuleFrame
import com.opencapture.openinstacine.monitor.LiveType
import com.opencapture.openinstacine.monitor.LocalMonitorGlass
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.openinstacine.monitor.MonitorGlass
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.openinstacine.monitor.OperatorPrefs
import com.opencapture.opencine.cameracontrols.AssistAudioOverlay
import com.opencapture.openinstacine.monitor.assists.AssistRect
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.cameracontrols.MirrorAssist
import com.opencapture.openinstacine.monitor.feed.rememberLiveFeedEffectsPlan
import com.opencapture.opencine.vocabulary.PlaybackLutColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import com.opencapture.opencine.media.MonitorAudioMeterChannel
import com.opencapture.opencine.media.MonitorAudioMeterLevels
import com.opencapture.monitorui.MonitorPlaybackGestureConfig
import com.opencapture.monitorui.MonitorPlaybackZoom
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaClipFormatting
import com.opencapture.opencine.media.PlaybackVideoLayout
import com.opencapture.opencine.cameracontrols.MediaCornerShape
import com.opencapture.opencine.cameracontrols.MediaOperatorCopy
import com.opencapture.opencine.cameracontrols.MediaCircleIconButton
import com.opencapture.opencine.cameracontrols.LocalMediaBackdropGlass

/// Captured source/cache addresses and bounded Bitmap decoding; shared UI owns the photo page.
@Composable
fun MediaPhotoViewer(model: AppModel, file: MediaFile, controller: LunaMediaPlaybackAdapter, onClose: () -> Unit,
    coverPresented: Boolean = false, onDeliver: (MediaFile) -> Unit = {},
    opening: MonitorMediaGalleryOpen<LunaMediaLibraryPayload>? = null,
) {
    val library = controller.library
    // A supplied gallery opening retains its original record and source token.
    val admission = opening?.admission ?: remember(library, file.id) { library.actionToken }
    val source = remember(library, opening?.id, file.id) { model.shell.state.value.monitor?.id }
    val record = opening?.record ?: controller.record(file)
    if (record == null) {
        com.opencapture.opencine.cameracontrols.MonitorOperatorMediaUnavailable(close = onClose); return
    }
    val loaders = com.opencapture.opencine.appkit.MonitorMediaPictureLoaders<LunaMediaLibraryPayload, Bitmap>(
        cached = { request ->
            if (!request.isCurrent()) null else (controller.localFile(request.record.payload.file) ?: controller.thumbnailFile(request.record.payload.file))?.let { location ->
                withContext(Dispatchers.IO) { MonitorBitmapDecoder.decode(location, MonitorBitmapDecoder.PAGE_EDGE) }
            }
        }, source = { request ->
            if (!request.isCurrent()) null else {
                val location = controller.cacheForPlayback(request.record.payload.file)
                if (location == null || !request.isCurrent()) null
                else withContext(Dispatchers.IO) { MonitorBitmapDecoder.decode(location, MonitorBitmapDecoder.PAGE_EDGE) }
            }
        })
    val operations = com.opencapture.opencine.appkit.MonitorMediaGalleryOperations<LunaMediaLibraryPayload>(
        delete = if (controller.canDelete(file)) { { controller.delete(it.payload.file); Unit } } else null,
        favorite = { controller.toggleFavorite(it.payload.file) })
    com.opencapture.opencine.cameracontrols.MonitorOperatorPhotoScreen(library, record, model.assist,
        loaders, operations, onClose, admission = admission, coverPresented = coverPresented,
        policy = com.opencapture.opencine.appkit.MonitorMediaPictureLoadPolicy.FIRST_AVAILABLE,
        sourceCurrent = { model.shell.state.value.monitor?.id == source },
        share = { request -> if (request.isCurrent()) onDeliver(request.record.payload.file) })
}

/** Real one-record SDK/native adapters; complete page behavior belongs to the shared player. */
@Composable
fun MediaPlayerScreen(files: List<MediaFile>, startingAt: MediaFile, controller: LunaMediaPlaybackAdapter,
    model: AppModel, onClose: () -> Unit, onDeliver: (MediaFile) -> Unit = {},
    coverPresented: Boolean = false,
    opening: MonitorMediaGalleryOpen<LunaMediaLibraryPayload>? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var composition by remember(controller) { mutableStateOf<Media3PlaybackOwner<LunaMediaLibraryPayload, LunaPlaybackLook>?>(null) }
    val owner = remember(controller) {
        com.opencapture.opencine.appkit.MonitorOperatorMediaModel<LunaMediaLibraryPayload, LunaPlaybackLook>(controller.library,
            scope = scope, makeAdmittedPlayback = { _, admission ->
                composition?.close()
                if (!admission.isCurrent()) null else {
                    val next = Media3PlaybackOwner(context, controller.library, controller::playbackCandidates,
                        controller::resolvePlaybackLook, controller::playbackAdmission) { it.file.fps?.toDouble() }
                    if (!admission.isCurrent()) { next.close(); null } else {
                        composition = next
                        if (!admission.isCurrent()) { next.close(); null } else next.playback
                    }
                }
            })
    }
    val outer by owner.state.collectAsState()
    val state = outer.playback?.state?.collectAsState()?.value
    val active = state?.active?.payload?.file ?: startingAt
    val initial = remember(owner, opening?.id, startingAt.id) { opening ?: controller.record(startingAt)?.let { record ->
        com.opencapture.opencine.appkit.MonitorMediaGalleryOpen(record,
            (if (files.any { it.id == startingAt.id }) files else listOf(startingAt)).mapNotNull(controller::record),
            controller.library.actionToken)
    } }
    DisposableEffect(owner) { onDispose { owner.closePlayback(); composition?.close() } }
    if (initial == null) {
        com.opencapture.opencine.cameracontrols.MonitorOperatorMediaUnavailable(close = onClose); return
    }
    val status by model.session.chromeStatus.collectAsState()
    val color = state?.look?.source?.colorMode ?: -1
    val effects = rememberLiveFeedEffectsPlan(model.assist, model.lutSelection, status,
        family = model.session.connectedCamera?.model?.family.orEmpty(), cameraName = model.session.connectedCamera?.name,
        playback = true, clipColorMode = color)
    val base = com.opencapture.openinstacine.monitor.rememberOperatorAssistSource(model, status)
    val resolvedColor = PlaybackLutColor.resolve(clip = color, live = status.colorMode,
        last = OperatorPrefs.lastMonitorColorMode(context))
    val picker = base.lookPicker?.let {
        com.opencapture.opencine.cameracontrols.AssistLutPicker(it.copy, it.selection, it.onSelect, it.library, it.profile, resolvedColor)
    }
    val assists = com.opencapture.opencine.cameracontrols.MonitorOperatorAssistSource(base.host, base.scopes,
        base.scopeStackMoved, picker, preview = { tool ->
        com.opencapture.openinstacine.monitor.assists.AssistInspectorImagePreview(tool, model.assist, model, model.lutSelection, resolvedColor, true)
    })
    val operations = com.opencapture.opencine.appkit.MonitorOperatorPlaybackOperations<LunaMediaLibraryPayload, LunaPlaybackLook>(
        cacheOriginal = if (controller.isLive && controller.library.canTransfer) { { record -> controller.download(record.payload.file) } } else null,
        delete = if (controller.canDelete(active)) { { record -> run { controller.delete(record.payload.file); controller.library.record(record.asset.id) == null } } } else null,
        favorite = { record -> controller.toggleFavorite(record.payload.file) },
        adoptLook = { _, look -> controller.rememberPlaybackLook(look.source) })
    val backdrop = rememberMonitorBackdropFeed(active.id, enabled = state?.ready == true)
    CompositionLocalProvider(LocalMonitorBackdrops provides listOf(backdrop.source),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides LiveDesign.feedWell) {
        com.opencapture.opencine.cameracontrols.MonitorOperatorPlaybackScreen(owner, initial, model.assist, assists,
            OperatorPrefs, effects, model.cacheFullResolution, coverPresented, operations,
            source = { record ->
                val file = record.payload.file
                com.opencapture.opencine.media.MonitorPlaybackSourceValues(
                    availability = when {
                        controller.isDownloaded(file) -> com.opencapture.opencine.media.MonitorPlaybackAvailability.ORIGINAL
                        controller.cacheGrade(file).isProxyOnly -> com.opencapture.opencine.media.MonitorPlaybackAvailability.PROXY
                        else -> com.opencapture.opencine.media.MonitorPlaybackAvailability.CAMERA
                    }, progress = controller.downloadProgress[file.path]?.toDouble(),
                    bufferedThroughSeconds = composition?.takeIf { current ->
                        val playback = owner.state.value.playback
                        playback != null && playback === current.playback && playback.state.value.ready &&
                            playback.state.value.active?.asset?.id == record.asset.id
                    }?.let { current -> current.native.bufferedThroughSeconds(current.playback.state.value.token) },
                    transfer = state?.look?.transfer)
            }, nativeAudio = { player -> composition?.takeIf { it.playback === player }?.audio },
            close = onClose, share = { record -> onDeliver(record.payload.file) }) { player, plan, geometry ->
            val native = composition?.takeIf { it.playback === player }?.native
            if (native != null) {
                val current by player.state.collectAsState()
                val mirror = model.assist.isPlaybackVisible(com.opencapture.monitorui.MonitorAssistTool.MIRROR)
                PlaybackFeedView(native, model.scopeBus, model.inspectorPreview, backdrop, plan,
                    mirrored = mirror && model.assist.mirrorHorizontal, flippedVertically = mirror && model.assist.mirrorVertical,
                    zoom = geometry.zoom, sourceWidth = native.player.videoSize.width.takeIf { it > 1 } ?: 1280,
                    sourceHeight = native.player.videoSize.height.takeIf { it > 1 } ?: 720,
                    sourceIdentity = current.token, sourceReady = current.ready,
                    sourceAdmission = owner::isCurrent, modifier = Modifier.fillMaxSize())
            }
        }
    }
}
