package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.*
import com.opencapture.monitorui.portraitZones
import com.opencapture.monitorui.portraitOnFeedControls
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import com.opencapture.monitorui.MonitorBackdropSource
import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.graphics.scale
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.opencapture.opencine.cameracontrols.LiveGimbalPanel
import com.opencapture.opencine.cameracontrols.LiveGimbalSheetHost
import com.opencapture.opencine.cameracontrols.LivePickerHost
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.cameracontrols.PortraitFeedAspect

/**
 * Debug-only, deterministic visual review of production chrome. This activity
 * never starts discovery, connects a camera, starts a decoder, or fabricates a
 * connected session. Intents choose the fixture capabilities and source aspect.
 */
class MonitorPreviewActivity : ComponentActivity() {
    private lateinit var model: AppModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getStringExtra("surface") == "reporting-consent") {
            // Preview the real layout without reading or changing reporting consent.
            setContent {
                OpenInstaCineTheme {
                    com.opencapture.opencine.appkit.diagnostics.AutomaticReportsPrompt(
                        product = com.opencapture.openinstacine.monitor.diagnostics.AppDiagnostics.host.product,
                        onPrivacy = {}, onEnable = {}, onNotNow = {},
                    )
                }
            }
            return
        }
        enableEdgeToEdge()
        WindowCompat.getInsetsController(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        model = AppModel(applicationContext)
        val capabilities = MonitorLayoutCapabilities(
            gimbal = intent.getBooleanExtra("gimbal", true),
            zoom = intent.getBooleanExtra("zoom", true),
            focus = intent.getBooleanExtra("focus", true),
            timecode = intent.getBooleanExtra("timecode", true),
        )
        val sourceAspect = intent.getFloatExtra("aspect", 16f / 9f).takeIf { it > 0f } ?: 16f / 9f
        setContent {
            OpenInstaCineTheme {
                CompositionLocalProvider(LocalMonitorGlass provides remember { MonitorGlass(GlassTier.FLAT) }) {
                    if (intent.getStringExtra("surface") == "catalog") {
                        ReviewClipCapabilities(intent.getBooleanExtra("clipStar", false))
                    } else {
                        ReviewMonitor(model, capabilities, sourceAspect,
                            intent.getFloatExtra("safeTop", 0f), intent.getFloatExtra("safeBottom", 0f),
                            intent.getBooleanExtra("patterned", false))
                    }
                    model.liveCover()?.let { cover -> ShellPage(model, cover) }
                }
            }
        }
    }

    override fun onDestroy() {
        if (::model.isInitialized) model.close()
        super.onDestroy()
    }
}

@Composable
private fun ReviewMonitor(model: AppModel, capabilities: MonitorLayoutCapabilities, sourceAspect: Float,
    safeTop: Float, safeBottom: Float, patterned: Boolean = false) {
    val status = remember(capabilities) {
        CameraStatus(batteryPercent = 80, storageTotalMb = 131072, storageFreeMb = 109568,
            timecode = if (capabilities.timecode) "15:39:50:00" else null,
            shootingMode = 1, iso = 1600, isoIndex = 7, shutterDenom = 50,
            expoMode = CameraCommands.EXPO_MANUAL, colorMode = CameraCommands.COLOR_DLOG2,
            resolutionCode = CameraCommands.RES_4K, fps = 25, fpsIndex = 2,
            wbMode = 6, wbKelvin = 5600, focusMode = 2, focusTrack = 0, audioChannel = 2, audioMetersLeft = -21.0, audioMetersRight = -14.0)
    }
    val cover = model.liveCover()
    LaunchedEffect(cover) {
        if (cover != null) model.assist.configureTool = null
    }
    val liveState = remember(model) { MonitorOperatorLiveState() }
    val context = LocalContext.current
    val image = remember(context, patterned) {
        if (patterned) context.assets.open("monitor_backdrop_reference.png").use { BitmapFactory.decodeStream(it) } else null
    }
    val backdrop = remember(image) { MonitorBackdropSource().apply {
        this.image = image?.let { it.scale(180, 120) }
    } }
    val readoutRegions = remember { com.opencapture.monitorui.MonitorReadoutRegions() }
    CompositionLocalProvider(
        LocalMonitorBackdrops provides if (image != null) listOf(backdrop) else emptyList(),
        com.opencapture.monitorui.LocalMonitorReadoutRegions provides readoutRegions,
    ) {
        BoxWithConstraints(Modifier.fillMaxSize().background(LiveDesign.background)) {
            val geometry = monitorOperatorLiveLayout(
                MonitorOperatorViewport(maxWidth.value, maxHeight.value, 0f, 0f, safeTop, safeBottom, 1f, safeTop > 0f),
                model.assist, model::chromeSectionMounts, model.portraitFeedAspect, sourceAspect, sourceAspect < 1f,
                model.virtualJoystickSize, false)
            val chrome = rememberOperatorChromeSource(model, status, capabilities)
            MonitorOperatorLiveSurface(chrome, geometry, liveState,
                cameraStatusLiveSource(chrome, geometry, liveState, "25", 4, hasPicture = true,
                    verticalPicture = sourceAspect < 1f, mirrored = false, recovering = false, busy = false, note = null,
                    clearNote = {}, readExposure = { -1 }, exposureAvailable = false, level = null, levelViewFlip = false,
                    vpnActive = { false }),
                rememberOperatorAssistSource(model, status),
                MonitorOperatorFocusObservation(null, com.opencapture.opencine.vocabulary.TrackingHud(), false, false, false, false),
                MonitorOperatorFocusActions({ _, _ -> }, {}, { false }, { false }, {}, { false }, {}, {}, {}),
                nativeInputBlocked = {},
                picture = {
                    if (image != null) Image(image.asImageBitmap(), null,
                        Modifier.liveModuleFrame(geometry.pictureContent).monitorBackdropSource(backdrop),
                        contentScale = ContentScale.FillBounds)
                    else Box(Modifier.liveModuleFrame(geometry.pictureContent).background(Color(0xFF4A4C48)))
                })
        }
    }
}

/** Real shared card layouts with identical data and different optional actions. */
@Composable
private fun ReviewClipCapabilities(canFavorite: Boolean) {
    var favorite by remember { mutableStateOf(false) }
    val clip = com.opencapture.monitorui.MonitorClipValue(
        "fixture", "Fixture clip", "4K · 25p", "00:12", "LOCAL", favorite)
    val toggle: (() -> Unit)? = if (canFavorite) ({ favorite = !favorite }) else null
    androidx.compose.foundation.layout.Column(
        Modifier.fillMaxSize().background(com.opencapture.monitorui.MonitorPalette.background)
            .padding(16.dp),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(16.dp),
    ) {
        androidx.compose.material3.Text("Camera capabilities",
            style = com.opencapture.monitorui.MonitorTypography.text(20f))
        for (list in listOf(false, true)) {
            com.opencapture.monitorui.MonitorClipCard(clip, list, selecting = false, selected = false,
                onOpen = {}, onSelect = {}, onFavorite = toggle) {
                Box(Modifier.fillMaxSize().background(Color(0xFF4A4C48)))
            }
        }
    }
}
