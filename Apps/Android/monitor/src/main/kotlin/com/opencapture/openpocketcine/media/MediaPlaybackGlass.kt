package com.opencapture.openpocketcine.media

import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.opencine.vocabulary.inferred

import android.app.ActivityManager
import android.graphics.Bitmap
import android.os.Build
import android.view.TextureView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.MonitorGlass
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import com.opencapture.opencine.vocabulary.ScopeExposureCeiling
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Compatibility environment; shared monitor materials receive passive image sources separately. */
@Composable
fun rememberPlaybackMonitorGlass(): MonitorGlass {
    return remember { MonitorGlass(com.opencapture.openpocketcine.GlassTier.FLAT) }
}

/** Edge scrims keep filename and transport controls readable over the picture. */
@Composable
fun BoxScope.PlaybackDarkenedBars(
    showTop: Boolean = true,
    showBottom: Boolean = true,
) {
    if (showTop) {
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .height(PlaybackChromeMetrics.topScrimDp.dp)
                .clipToBounds()
                .background(
                    Brush.verticalGradient(
                        listOf(LiveDesign.playbackScrim, Color.Transparent),
                    ),
                ),
        )
    }
    if (showBottom) {
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(PlaybackChromeMetrics.bottomScrimDp.dp)
                .clipToBounds()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, LiveDesign.playbackScrim),
                    ),
                ),
        )
    }
}

/** Static photo input follows the same passive geometry contract as video. */
@Composable
internal fun rememberPhotoBackdrop(bitmap: Bitmap?, identity: Any): com.opencapture.monitorui.MonitorBackdropSource {
    val source = remember { com.opencapture.monitorui.MonitorBackdropSource() }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var resumed by remember { androidx.compose.runtime.mutableStateOf(false) }
    androidx.compose.runtime.DisposableEffect(source, lifecycle) {
        fun update() { resumed = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
            if (!resumed) source.image = null }
        val observer = androidx.lifecycle.LifecycleEventObserver { _, _ -> update() }
        lifecycle.addObserver(observer); update()
        onDispose { lifecycle.removeObserver(observer); source.image = null }
    }
    LaunchedEffect(bitmap, identity, resumed) {
        source.image = null
        if (bitmap != null && resumed) {
            source.image = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                val scale = minOf(1f, 213f / bitmap.width, 120f / bitmap.height)
                bitmap.scale(
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                )
            }
        }
    }
    return source
}
