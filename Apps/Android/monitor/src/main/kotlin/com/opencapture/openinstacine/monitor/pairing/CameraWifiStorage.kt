package com.opencapture.openinstacine.monitor.pairing

import android.content.Context
import com.opencapture.opencine.insta360.luna.LunaStationNetwork
import com.opencapture.opencine.platform.CameraWifiStorageConfiguration
import com.opencapture.opencine.platform.SharedNetworkStore

/**
 * Where the Luna's camera Wi-Fi credentials live: the namespace inherited from OpenPocketCine, which
 * is the installed users' data contract (never rename it without a migration). The store itself is
 * the platform's [com.opencapture.opencine.platform.CameraWifiCredentialStore]; the Luna backend
 * reads and writes it off Main through the shared credential IO helper.
 */
val cameraWifiStorage: CameraWifiStorageConfiguration =
    CameraWifiStorageConfiguration(
        preferencesName = "openpocketcine.camera-wifi",
        keyAlias = "openpocketcine.camera-wifi",
        ssidKeySuffix = ".ssid",
        passwordKeySuffix = ".password",
        ssidIndexPrefix = "ssid:",
    )

/**
 * Wi-Fi and hotspot setups (Add setup): names in their own preferences, passwords sealed with a
 * device-only Keystore key. The Luna backend reads and writes them off Main.
 */
class StationNetworkStorage(context: Context) {
    private val store = SharedNetworkStore(context, STATION_NETWORKS, STATION_NETWORKS)

    fun load(): List<LunaStationNetwork> = store.savedNetworks().map { LunaStationNetwork(it.ssid, it.password, it.hotspot) }

    fun save(network: LunaStationNetwork) = store.save(network.ssid, network.password, network.hotspot)

    private companion object {
        /** The data contract for saved setups: never rename it without a migration. */
        const val STATION_NETWORKS = "openinstacine.station-networks"
    }
}
