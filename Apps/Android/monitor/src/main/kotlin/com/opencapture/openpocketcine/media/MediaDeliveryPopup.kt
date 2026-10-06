package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.MediaShare
import com.opencapture.monitorui.MonitorMediaDeliveryValue
import com.opencapture.monitorui.MonitorMediaDeliveryPanel
import com.opencapture.monitorui.MonitorMediaDeliveryProgress
import com.opencapture.monitorui.MonitorMediaDeliveryProgressValue
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import com.opencapture.monitorui.monitorScrollFade
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.opencine.appkit.MonitorDeliveryCompletion
import com.opencapture.opencine.appkit.MonitorDeliveryModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.cameracontrols.admittedDeliveryToast
import com.opencapture.opencine.cameracontrols.MediaDeliveryResult
import com.opencapture.opencine.cameracontrols.MediaCapsuleShape

enum class MediaDeliveryDestination(
    val title: String,
    val subtitle: String,
    val actionTitle: String,
) {
    NATIVE_SHARE(
        title = "Share",
        subtitle = "Nearby Share, Files, and other apps",
        actionTitle = "Share",
    ),
}

/** Listed on the Share sheet; never selectable and never starts auth or upload. */
internal object MediaDeliveryUpcoming {
    val titles = listOf(
        "Google Drive",
        "Dropbox",
        "NAS (SMB)",
        "LucidLink",
        "Backblaze B2",
        "Vimeo Review",
    )
}

enum class MediaDeliveryPostExportAction {
    SYSTEM_SHARE,
    SAVE_TO_PHOTOS,
}

data class MediaDeliveryOverlayState(
    val statusLine: String,
    val batchLine: String? = null,
    val overallFraction: Double = 0.0,
    val isPreparing: Boolean = true,
    val filename: String? = null,
)

private enum class DeliveryStep {
    DESTINATION,
    OPTIONS,
}

@Composable
fun MediaDeliveryHost(
    files: List<MediaFile>?,
    controller: LunaMediaPlaybackAdapter,
    onDismissPopup: () -> Unit,
) {
    val context = LocalContext.current
    // One explicit composition lifetime owns both resources and disposal ordering.
    val scope = remember(controller) { CoroutineScope(SupervisorJob() + Dispatchers.Main) }
    val delivery = remember(scope) {
        MonitorDeliveryModel<MediaDeliveryOverlayState, MediaDeliveryResult, Unit>(scope)
    }
    DisposableEffect(delivery, scope) {
        onDispose {
            delivery.close()
            scope.cancel()
        }
    }
    val state by delivery.state.collectAsState()
    val overlay = state.progress
    val toast = state.toast

    if (files == null && !state.running && overlay == null && toast == null) return

    Box(Modifier.fillMaxSize()) {
        files?.let { selection ->
            MediaDeliveryPopup(
                files = selection,
                controller = controller,
                busy = state.running,
                onDismiss = onDismissPopup,
                onDeliver = { action ->
                    delivery.begin(
                        onComplete = { outcome ->
                            admittedDeliveryToast(outcome) { ready -> shareFiles(context, ready) }
                        },
                    ) { progress ->
                        progress(MediaDeliveryOverlayState(statusLine = "Preparing…", isPreparing = true))
                        val outcome = runDelivery(
                            context = context, controller = controller, files = selection,
                            action = action, onProgress = progress,
                        )
                        MonitorDeliveryCompletion(outcome)
                    }
                    onDismissPopup()
                },
            )
        }
        overlay?.let { progress ->
            MediaDeliveryProgressOverlay(
                progress,
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 12.dp),
            )
        }
        toast?.let { message ->
            MediaDeliveryCompletionToast(message, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}
@Composable
fun MediaDeliveryPopup(
    files: List<MediaFile>,
    controller: LunaMediaPlaybackAdapter,
    onDismiss: () -> Unit,
    onDeliver: (MediaDeliveryPostExportAction) -> Unit,
    busy: Boolean = false,
) {
    var step by remember { mutableStateOf(DeliveryStep.DESTINATION) }
    var destination by remember { mutableStateOf<MediaDeliveryDestination?>(null) }
    var shareAction by remember { mutableStateOf(MediaDeliveryPostExportAction.SYSTEM_SHARE) }
    val cachedCount = files.count { controller.isDownloaded(it) }
    val hasDeliverable = cachedCount > 0 || (controller.isLive && files.isNotEmpty())
    val canContinue = destination == MediaDeliveryDestination.NATIVE_SHARE && hasDeliverable && !busy

    Dialog(
        onDismissRequest = {
            when {
                busy -> Unit
                step == DeliveryStep.OPTIONS -> step = DeliveryStep.DESTINATION
                else -> onDismiss()
            }
        },
        properties =
            DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
    ) {
    val dialogView = LocalView.current
    DisposableEffect(dialogView) {
        val window = (dialogView.parent as? DialogWindowProvider)?.window
        window?.setDimAmount(0f)
        window?.let {
            com.opencapture.opencine.appkit.applyMonitorSystemBars(it)
        }
        onDispose { }
    }
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = .42f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {
                if (!busy) onDismiss()
            },
        contentAlignment = Alignment.BottomCenter,
    ) {
        val notices = if (cachedCount < files.size) listOf(MonitorMediaDeliveryValue.Notice(
            if (controller.isLive) "${files.size - cachedCount} on-camera clip(s) will be cached from the camera first."
            else "${files.size - cachedCount} on-camera clip(s) will be skipped; reconnect to cache them."
        )) else emptyList()
        val nativeShare = MediaDeliveryDestination.NATIVE_SHARE
        MonitorMediaDeliveryPanel(
            value = MonitorMediaDeliveryValue(
                step = if (step == DeliveryStep.DESTINATION) MonitorMediaDeliveryValue.Step.DESTINATION else MonitorMediaDeliveryValue.Step.OPTIONS,
                title = destination?.title ?: "Share",
                selectionLabel = "${files.size} clip${if (files.size == 1) "" else "s"}",
                notices = notices,
                destinations = listOf(MonitorMediaDeliveryValue.Destination(nativeShare.name, nativeShare.title, nativeShare.subtitle, hasDeliverable)),
                upcoming = MediaDeliveryUpcoming.titles,
                export = if (step == DeliveryStep.OPTIONS && files.size == 1)
                    MonitorMediaDeliveryValue.Export(filename = files.first().filename) else null,
                footer = if (step == DeliveryStep.OPTIONS) MonitorMediaDeliveryValue.Footer(
                    postExport = MonitorMediaDeliveryValue.Choices("", options = listOf(
                        MonitorMediaDeliveryValue.Choice(MediaDeliveryPostExportAction.SYSTEM_SHARE.name, "Share"),
                        MonitorMediaDeliveryValue.Choice(MediaDeliveryPostExportAction.SAVE_TO_PHOTOS.name, "Save to Photos")
                    ), selectedID = shareAction.name),
                    actionTitle = if (shareAction == MediaDeliveryPostExportAction.SAVE_TO_PHOTOS) "Save to Photos" else "Share",
                    enabled = canContinue
                ) else null
            ),
            onAction = { action ->
                when (action) {
                    MonitorMediaDeliveryValue.Action.Close -> onDismiss()
                    MonitorMediaDeliveryValue.Action.Back -> step = DeliveryStep.DESTINATION
                    MonitorMediaDeliveryValue.Action.Begin -> if (canContinue) onDeliver(shareAction)
                    is MonitorMediaDeliveryValue.Action.Destination -> if (action.id == nativeShare.name && hasDeliverable) {
                        destination = nativeShare; step = DeliveryStep.OPTIONS
                    }
                    is MonitorMediaDeliveryValue.Action.Selection -> if (action.selection == MonitorMediaDeliveryValue.Selection.POST_EXPORT) {
                        MediaDeliveryPostExportAction.entries.firstOrNull { it.name == action.id }?.let { shareAction = it }
                    }
                    else -> Unit // This adapter supplies no other optional controls or service.
                }
            },
            modifier = Modifier.navigationBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp)
                .widthIn(max = 620.dp).fillMaxWidth(),
            destinationIcon = { OpcIcon(OpcIcon.SHARE, null, Modifier.size(18.dp), LiveDesign.text) }
        )
    }
    }
}

@Composable
fun MediaDeliveryProgressOverlay(
    state: MediaDeliveryOverlayState,
    onCancel: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    MonitorMediaDeliveryProgress(
        value = MonitorMediaDeliveryProgressValue(state.statusLine, state.batchLine, state.overallFraction, state.isPreparing),
        onCancel = onCancel,
        modifier = modifier.widthIn(max = 420.dp),
        destinationIcon = { OpcIcon(OpcIcon.SHARE, null, Modifier.size(13.dp), LiveDesign.accent) }
    )
}

@Composable
fun MediaDeliveryCompletionToast(message: String, modifier: Modifier = Modifier) {
    Text(
        message,
        style = LiveType.ui(13f, FontWeight.Medium),
        color = LiveDesign.text,
        modifier =
            modifier
                .navigationBarsPadding()
                .padding(bottom = 28.dp)
                .clip(MediaCapsuleShape)
                .mediaSheetPlate(MediaCapsuleShape)
                .padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

private suspend fun runDelivery(
    context: Context,
    controller: LunaMediaPlaybackAdapter,
    files: List<MediaFile>,
    action: MediaDeliveryPostExportAction,
    onProgress: (MediaDeliveryOverlayState) -> Unit,
): MediaDeliveryResult {
    // Original camera file only — never the LRF/XRF 720p playback proxy.
    val toCache = files.filter { !controller.isDownloaded(it) }
    if (toCache.isNotEmpty()) {
        coroutineScope {
            for ((index, file) in toCache.withIndex()) {
                fun emit(fraction: Double) {
                    onProgress(
                        MediaDeliveryOverlayState(
                            statusLine =
                                if (fraction > 0.0) "Caching from camera" else "Caching from camera…",
                            batchLine = if (toCache.size > 1) "Clip ${index + 1} of ${toCache.size}" else null,
                            overallFraction = fraction,
                            isPreparing = fraction <= 0.0,
                            filename = file.filename,
                        ),
                    )
                }
                emit(controller.downloadProgress[file.path] ?: 0.0)
                val poll =
                    launch {
                        while (isActive) {
                            delay(200)
                            emit(controller.downloadProgress[file.path] ?: 0.0)
                        }
                    }
                try {
                    controller.download(file)
                } finally {
                    poll.cancel()
                }
            }
        }
    }
    val ready =
        files.mapNotNull { file ->
            if (controller.isDownloaded(file)) controller.localFile(file) else null
        }
    if (ready.isEmpty()) {
        return MediaDeliveryResult.Message(if (toCache.isNotEmpty()) {
            "Couldn't cache ${toCache.size} clip(s) from the camera — check the connection and try again."
        } else {
            "Select at least one clip."
        })
    }
    return when (action) {
        MediaDeliveryPostExportAction.SYSTEM_SHARE -> {
            for ((index, file) in ready.withIndex()) {
                onProgress(
                    MediaDeliveryOverlayState(
                        statusLine = "Preparing to share",
                        batchLine = if (ready.size > 1) "Clip ${index + 1} of ${ready.size}" else null,
                        overallFraction = (index + 1).toDouble() / ready.size,
                        isPreparing = false,
                        filename = file.name,
                    ),
                )
            }
            MediaDeliveryResult.ShareReady(ready)
        }
        MediaDeliveryPostExportAction.SAVE_TO_PHOTOS -> {
            var saved = 0
            for ((index, file) in ready.withIndex()) {
                onProgress(
                    MediaDeliveryOverlayState(
                        statusLine = "Saving to Photos ${(index * 100 / ready.size)}%",
                        batchLine = if (ready.size > 1) "Clip ${index + 1} of ${ready.size}" else null,
                        overallFraction = (index + 1).toDouble() / ready.size,
                        isPreparing = false,
                        filename = file.name,
                    ),
                )
                val ok =
                    withContext(Dispatchers.IO) {
                        insertIntoGallery(context, file) != null
                    }
                if (ok) saved += 1
            }
            MediaDeliveryResult.Message(
                if (saved == 0) "Couldn't save clips to Photos."
                else "Saved $saved clip${if (saved == 1) "" else "s"} to Photos"
            )
        }
    }
}

private val mediaShare = MediaShare(album = "OpenInstaCine")

private fun shareFiles(context: Context, files: List<File>): Boolean =
    mediaShare.shareFiles(context, files, MediaHTTP::playbackMIMEType)

private fun insertIntoGallery(context: Context, file: File): Uri? =
    mediaShare.insertIntoGallery(context, file, MediaHTTP.playbackMIMEType(file.name))
