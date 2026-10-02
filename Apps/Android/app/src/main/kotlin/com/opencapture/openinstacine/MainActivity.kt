package com.opencapture.openinstacine

import android.os.Bundle
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.openpocketcine.MonitorConfiguration
import com.opencapture.openpocketcine.BrandIdentity
import com.opencapture.openpocketcine.pairing.CameraWifiCredentialStore

/** Storefront identity and adapter only; every screen comes from the shared monitor. */
class MainActivity : com.opencapture.openpocketcine.MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val replay = BuildConfig.DEBUG && intent.getBooleanExtra("local_replay", false)
        val brand = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna Ultra", sourceLabel = if (replay) "LOCAL REPLAY · NOT A LIVE CAMERA" else null)
        MonitorConfiguration.install(brand, cameraLooks = LunaCameraLooks.entries) { context ->
            if (replay) Class.forName("com.opencapture.openinstacine.LocalReplayBackend").getConstructor(android.content.Context::class.java).newInstance(context) as com.opencapture.opencine.insta360.shell.CameraBackend
            else CameraWifiCredentialStore(context).let { wifi -> LunaBackend(context, savedWifi = wifi::load, saveWifi = wifi::save) }
        }
        super.onCreate(savedInstanceState)
    }
}
