package com.opencapture.openinstacine.monitor

import android.content.Context
import com.opencapture.opencine.insta360.shell.CameraBackend
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.opencine.vocabulary.LutEntry

/** App identity the shell shows. App-owned (not part of the Insta360 shell contract). */
data class BrandIdentity(val appName: String, val wordmark: String, val accentArgb: Long, val cameraFamily: String, val sourceUrl: String? = null, val supportUrl: String? = null, val issueUrl: String? = null, val featureUrl: String? = null, val sourceLabel: String? = null)

/** Installed by a thin brand launcher before constructing any shared screen/model. */
object MonitorConfiguration {
    var identity = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna Ultra")
        private set
    private var factory: ((Context) -> CameraBackend)? = null
    fun install(brand: BrandIdentity, cameraLooks: List<LutEntry> = emptyList(), backend: (Context) -> CameraBackend) {
        identity = brand
        com.opencapture.monitorui.MonitorPalette.accent = androidx.compose.ui.graphics.Color(brand.accentArgb)
        LutCatalog.configureCameraLooks(cameraLooks)
        factory = backend
    }
    /** Debug review only: replaces the installed backend, keeping the brand and camera looks. */
    internal fun replaceBackend(backend: (Context) -> CameraBackend) {
        factory = backend
    }
    fun createBackend(context: Context): CameraBackend = checkNotNull(factory) { "Brand launcher must install a camera backend" }(context)
}
