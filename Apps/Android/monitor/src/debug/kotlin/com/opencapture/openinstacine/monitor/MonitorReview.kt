package com.opencapture.openinstacine.monitor

import android.content.Context
import android.content.Intent
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.opencapture.monitorui.ReviewLaunch
import com.opencapture.opencine.appkit.MonitorMediaCatalogCapture
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.core.ConnectedCamera
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.insta360.luna.LunaFailures
import com.opencapture.opencine.platform.ReviewMediaSeed
import com.opencapture.opencine.platform.ReviewLiveVideoSeed
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.openinstacine.monitor.media.MediaCache
import com.opencapture.openinstacine.monitor.media.toJson
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

internal fun Modifier.reviewMetadata(review: ReviewLaunch?): Modifier =
    if (review == null) this else semantics { testTagsAsResourceId = true }

/** SIMULATED review through the production Luna cache, shared catalog and native player. */
internal object MonitorReview {
    private const val NAMESPACE = "SIMULATED-S1"

    /** The screens this host stages; anything else decodes null and runs the real startup. */
    private val screens = setOf(
        ReviewLaunch.Screen.CAMERAS, ReviewLaunch.Screen.PAIR, ReviewLaunch.Screen.LIVE,
        ReviewLaunch.Screen.MEDIA, ReviewLaunch.Screen.PLAYBACK, ReviewLaunch.Screen.SETTINGS,
        ReviewLaunch.Screen.CHROME_EDIT,
    )

    fun decode(intent: Intent?): ReviewLaunch? = ReviewLaunch.decode { intent?.getStringExtra(it) }
        ?.takeIf { it.source == ReviewLaunch.Source.LOCAL && !it.connected && it.screen in screens }

    /** Set the cache address and, for LIVE, the SIMULATED backend before model construction. */
    fun prepare(context: Context, review: ReviewLaunch?) {
        if (review == null) return
        context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE)
            .edit().putString("opc.media.lastCameraID", NAMESPACE).apply()
        // The two saved cameras, idle, under every staged screen (the review `state` names a
        // scripted pipeline, none is that page), so no staged cell starts on the first-run
        // pair wizard. Same records as the shipping app stores them.
        val legacy = context.getSharedPreferences(AppModel.LEGACY_CAMERAS, Context.MODE_PRIVATE)
        val records = JSONArray()
            .put(JSONObject()
                .put("id", "00000000-0000-0000-0000-000000000001").put("advertisedName", "Studio camera")
                .put("modelName", "Luna Ultra").put("lastConnectedAt", 1_000L)
                .put("wifiSSID", "Studio-5G").put("hotspotSSID", "Rig phone"))
            .put(JSONObject()
                .put("id", "00000000-0000-0000-0000-000000000002").put("advertisedName", "Travel camera")
                .put("modelName", "Luna Ultra").put("lastConnectedAt", 500L))
        legacy.edit().putString("records-json", records.toString()).apply()
        if (review.screen == ReviewLaunch.Screen.LIVE) {
            MonitorConfiguration.replaceBackend { SimulatedLiveBackend(input = ReviewLiveVideoSeed.frames(it.applicationContext)) }
            // Keep the staged cameras seeded above; the live session supplies its camera directly.
        }
    }

    suspend fun start(context: Context, model: AppModel, review: ReviewLaunch) {
        if (review.screen == ReviewLaunch.Screen.LIVE) {
            model.shell.present(ConnectedCamera(ShellReview.camera, ReviewLiveSession()))
            return
        }
        when (review.screen) {
            ReviewLaunch.Screen.PAIR -> model.shell.beginPairing()
            // The staged monitor is the real session's control seam, idle: the live chrome renders
            // over it, and no radio, connection or command ever reaches a camera.
            ReviewLaunch.Screen.CHROME_EDIT -> model.session.lunaPort?.openSession()?.let { session ->
                model.shell.present(ConnectedCamera(
                    SavedCamera(STAGED_CAMERA, LunaFailures.INTEGRATION,
                        advertisedName = "SIMULATED common input", model = "Luna Ultra"),
                    session))
                // The chrome editor over the same staged monitor (iOS `beginChromeEditing`).
                if (review.screen == ReviewLaunch.Screen.CHROME_EDIT) model.beginChromeEditing(model.currentDispMode)
            }
            ReviewLaunch.Screen.MEDIA, ReviewLaunch.Screen.PLAYBACK -> stageMedia(context, model, review)
            ReviewLaunch.Screen.SETTINGS -> {
                review.settingsTab?.let { model.operatorSettingsTab = it }
                model.shell.open(ShellModel.Cover.SETTINGS)
            }
            else -> Unit // CAMERAS: the seeded saved cameras leave the shell on the cameras page.
        }
    }

    private suspend fun stageMedia(context: Context, model: AppModel, review: ReviewLaunch) {
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

    private const val STAGED_CAMERA = "simulated-common-input"
}
