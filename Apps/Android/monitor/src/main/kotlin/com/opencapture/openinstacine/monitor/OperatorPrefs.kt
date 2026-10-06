package com.opencapture.openinstacine.monitor

import android.content.Context
import androidx.core.content.edit
import com.opencapture.opencine.cameracontrols.OperatorPreferenceStore
import com.opencapture.opencine.runtime.MonitorGlesUpscaler

typealias PocketDispMode = com.opencapture.opencine.appkit.MonitorDisplayMode
typealias PocketDispSection = com.opencapture.opencine.appkit.MonitorDisplaySection
typealias PocketDispChrome = com.opencapture.opencine.appkit.MonitorDisplayChrome

/** The operator's choices in this app's existing preferences file and keys. */
object OperatorPrefs : OperatorPreferenceStore(file = "openpocketcine.operator", keyPrefix = "OpenPocketCine.") {
    private val FEED_UPSCALER = key("feedUpscaler")

    fun feedUpscaler(context: Context): MonitorGlesUpscaler =
        MonitorGlesUpscaler.fromStored(prefs(context).getString(FEED_UPSCALER, null))

    fun setFeedUpscaler(context: Context, value: MonitorGlesUpscaler) {
        prefs(context).edit { putString(FEED_UPSCALER, value.label) }
    }
}
