package com.opencapture.openinstacine.monitor

import android.content.Context
import android.content.Intent
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.opencapture.monitorui.ReviewLaunch
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.MonitorMediaCatalogCapture
import com.opencapture.opencine.platform.ReviewMediaSeed
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.openinstacine.monitor.media.MediaCache
import com.opencapture.openinstacine.monitor.media.toJson
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray

internal fun Modifier.reviewMetadata(review: ReviewLaunch?): Modifier =
    if (review == null) this else semantics { testTagsAsResourceId = true }

/** SIMULATED local review through the production Luna cache, shared catalog and native player. */
internal object MonitorReview {
    private const val NAMESPACE = "SIMULATED-S1"

    fun decode(intent: Intent?): ReviewLaunch? = ReviewLaunch.decode { intent?.getStringExtra(it) }
        ?.takeIf { it.screen == ReviewLaunch.Screen.MEDIA && it.source == ReviewLaunch.Source.LOCAL && !it.connected }

    /** Set the existing cache address before the normal model constructs its library. */
    fun prepare(context: Context, review: ReviewLaunch?) {
        if (review != null) context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE)
            .edit().putString("opc.media.lastCameraID", NAMESPACE).apply()
    }

    suspend fun start(context: Context, model: AppModel, review: ReviewLaunch) {
        val records = withContext(Dispatchers.IO) {
            val cache = MediaCache(context.noBackupFilesDir,
                context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE), model.mediaStorage)
            check(model.mediaPlayback.cameraId == NAMESPACE)
            val clips = ReviewMediaSeed.write(File(context.cacheDir, NAMESPACE), review.mediaCount) { clip ->
                val file = file(clip)
                ReviewMediaSeed.Destination(cache.fileCache(NAMESPACE, file), cache.thumbnailFile(NAMESPACE, file))
            }
            val catalog = JSONArray().apply { clips.forEach { put(file(it).toJson()) } }
            cache.catalogFile(NAMESPACE).apply { parentFile?.mkdirs(); writeText(catalog.toString()) }
            model.mediaLibrary.cache.load().also { check(it.size == review.mediaCount) }
        }
        model.mediaLibrary.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = true, upserts = records),
            model.mediaLibrary.actionToken)
        model.mediaLibrary.display(layout = review.layout)
        model.shell.open(ShellModel.Cover.MEDIA)
    }

    private fun file(clip: ReviewMediaSeed.Clip): MediaFile = MediaFile(
        path = "DCIM/SIMULATED/${clip.filename}", thumbPath = "DCIM/SIMULATED/${clip.filename}",
        sizeBytes = clip.byteCount, durationSeconds = clip.durationSeconds,
        resolution = "${clip.width}x${clip.height}", fps = clip.frameRate,
    )
}
