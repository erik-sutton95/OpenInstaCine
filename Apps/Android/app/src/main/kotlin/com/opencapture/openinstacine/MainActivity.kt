package com.opencapture.openinstacine

import android.os.Bundle
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.openinstacine.monitor.MonitorConfiguration
import com.opencapture.openinstacine.monitor.BrandIdentity
import com.opencapture.opencine.platform.CameraWifiCredentialStore
import com.opencapture.openinstacine.monitor.pairing.StationNetworkStorage
import com.opencapture.openinstacine.monitor.pairing.cameraWifiStorage

/** Storefront identity and adapter only; every screen comes from the shared monitor. */
class MainActivity : com.opencapture.openinstacine.monitor.MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val replay = BuildConfig.DEBUG && intent.getBooleanExtra("local_replay", false)
        val brand = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna Ultra", sourceLabel = if (replay) "LOCAL REPLAY · NOT A LIVE CAMERA" else null)
        // A Multiview member: one more Luna connection with the same saved setups, on the shared path.
        val member: ((android.content.Context) -> LunaBackend)? = if (replay) null else { context ->
            CameraWifiCredentialStore(context, cameraWifiStorage).let { wifi ->
                val stations = StationNetworkStorage(context)
                LunaBackend(context, savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove,
                    savedStations = stations::load, keepStation = stations::save,
                    stationPath = MonitorConfiguration.stationPath(context))
            }
        }
        MonitorConfiguration.install(brand, cameraLooks = LunaCameraLooks.entries, multiviewMember = member) { context ->
            if (replay) Class.forName("com.opencapture.openinstacine.LocalReplayBackend").getConstructor(android.content.Context::class.java).newInstance(context) as com.opencapture.opencine.insta360.shell.CameraBackend
            else CameraWifiCredentialStore(context, cameraWifiStorage).let { wifi ->
                val stations = StationNetworkStorage(context)
                LunaBackend(context, savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove,
                    mediaTransfer = com.opencapture.openinstacine.monitor.media.LunaMediaTransferDriver(),
                    savedStations = stations::load, keepStation = stations::save,
                    stationPath = MonitorConfiguration.stationPath(context))
            }
        }
        super.onCreate(savedInstanceState)
    }
}
