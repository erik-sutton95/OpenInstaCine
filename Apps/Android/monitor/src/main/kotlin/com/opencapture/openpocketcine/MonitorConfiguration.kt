package com.opencapture.openpocketcine

import android.content.Context
import com.opencapture.openpocketcine.core.BrandIdentity
import com.opencapture.openpocketcine.core.CameraBackend

/** Installed by a thin brand launcher before constructing any shared screen/model. */
object MonitorConfiguration {
    var identity = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna Ultra")
        private set
    private var factory: ((Context) -> CameraBackend)? = null
    fun install(brand: BrandIdentity, backend: (Context) -> CameraBackend) { identity = brand; factory = backend }
    fun createBackend(context: Context): CameraBackend = checkNotNull(factory) { "Brand launcher must install a camera backend" }(context)
}
