package com.opencapture.openpocketcine

import android.content.Context
import com.opencapture.openpocketcine.core.BrandIdentity
import com.opencapture.openpocketcine.core.CameraBackend
import com.opencapture.openpocketcine.lut.LutCatalog
import com.opencapture.openpocketcine.lut.LutEntry

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
    fun createBackend(context: Context): CameraBackend = checkNotNull(factory) { "Brand launcher must install a camera backend" }(context)
}
