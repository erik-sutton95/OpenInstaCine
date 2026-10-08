package com.opencapture.openinstacine.monitor.media

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.opencapture.openinstacine.monitor.MonitorGlass

/** Compatibility environment; shared monitor materials receive passive image sources separately. */
@Composable
fun rememberPlaybackMonitorGlass(): MonitorGlass {
    return remember { MonitorGlass(com.opencapture.openinstacine.monitor.GlassTier.FLAT) }
}

/** Static photo input follows the same passive geometry contract as video. */
@Composable
internal fun rememberPhotoBackdrop(bitmap: Bitmap?, identity: Any): com.opencapture.monitorui.MonitorBackdropSource =
    com.opencapture.monitorui.rememberMonitorPhotoBackdrop(bitmap, identity)
