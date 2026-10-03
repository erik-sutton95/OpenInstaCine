package com.opencapture.openpocketcine.feed

typealias FeedUpscaler = com.opencapture.opencine.runtime.MonitorGlesUpscaler

/** GLES reads this off the UI thread. Operator Setup writes it with the prefs. */
object FeedUpscaleSwitch {
    @Volatile
    var rendererReads: FeedUpscaler = FeedUpscaler.FAST
}
