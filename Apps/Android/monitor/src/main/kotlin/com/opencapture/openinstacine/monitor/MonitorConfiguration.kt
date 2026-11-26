package com.opencapture.openinstacine.monitor

import android.content.Context
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.opencine.insta360.shell.CameraBackend
import com.opencapture.opencine.platform.SharedWiFiPath
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.opencine.vocabulary.LutEntry

/** App identity the shell shows. App-owned (not part of the Insta360 shell contract). */
data class BrandIdentity(val appName: String, val wordmark: String, val accentArgb: Long, val cameraFamily: String, val sourceUrl: String? = null, val supportUrl: String? = null, val issueUrl: String? = null, val featureUrl: String? = null, val sourceLabel: String? = null)

/** Installed by a thin brand launcher before constructing any shared screen/model. */
object MonitorConfiguration {
    var identity = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna")
        private set
    private var factory: ((Context) -> CameraBackend)? = null
    private var memberFactory: ((Context) -> LunaBackend)? = null
    // Holds the application context only (stationPath passes it), never an activity.
    @android.annotation.SuppressLint("StaticFieldLeak")
    private var path: SharedWiFiPath? = null

    /**
     * Installs the brand, its camera looks, the monitor's backend and, optionally, a Multiview
     * member's backend ([multiviewMember]: one more Luna connection on [stationPath]). Without one
     * the cameras page offers no Multiview.
     */
    fun install(
        brand: BrandIdentity,
        cameraLooks: List<LutEntry> = emptyList(),
        multiviewMember: ((Context) -> LunaBackend)? = null,
        backend: (Context) -> CameraBackend,
    ) {
        identity = brand
        com.opencapture.monitorui.MonitorPalette.accent = androidx.compose.ui.graphics.Color(brand.accentArgb)
        LutCatalog.configureCameraLooks(cameraLooks)
        factory = backend
        memberFactory = multiviewMember
    }

    /**
     * This process's one path to a Wi-Fi or hotspot setup's network: the monitor's backend and every
     * Multiview member pass it, so one connection's cleanup never unbinds another's network.
     */
    @Synchronized
    fun stationPath(context: Context): SharedWiFiPath =
        path ?: SharedWiFiPath(context.applicationContext, log = { _, _, message -> android.util.Log.i("LunaBackend", "luna: $message") })
            .also { path = it }

    /** Whether the launcher installed Multiview members. */
    val offersMultiview: Boolean get() = memberFactory != null

    /** A new Multiview member connection (a tile's, a commission's or a return's). */
    fun createMultiviewMember(context: Context): LunaBackend =
        checkNotNull(memberFactory) { "Brand launcher installed no Multiview member backend" }(context)
    /** Debug review only: replaces the installed backend, keeping the brand and camera looks. */
    internal fun replaceBackend(backend: (Context) -> CameraBackend) {
        factory = backend
    }
    fun createBackend(context: Context): CameraBackend = checkNotNull(factory) { "Brand launcher must install a camera backend" }(context)
}
