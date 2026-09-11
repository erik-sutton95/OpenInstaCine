package com.opencapture.openinstacine

import android.os.Bundle
import com.opencapture.openinstacine.luna.LunaBackend
import com.opencapture.openpocketcine.MonitorConfiguration
import com.opencapture.openpocketcine.core.BrandIdentity

/** Storefront identity and adapter only; every screen comes from the shared monitor. */
class MainActivity : com.opencapture.openpocketcine.MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val replay = BuildConfig.DEBUG && intent.getBooleanExtra("local_replay", false)
        val brand = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna Ultra", sourceLabel = if (replay) "LOCAL REPLAY · NOT A LIVE CAMERA" else null)
        MonitorConfiguration.install(brand, cameraLooks = LunaCameraLooks.entries) { context ->
            if (replay) Class.forName("com.opencapture.openinstacine.LocalReplayBackend").getConstructor(android.content.Context::class.java).newInstance(context) as com.opencapture.openpocketcine.core.CameraBackend
            else LunaBackend(context)
        }
        super.onCreate(savedInstanceState)
    }
}
