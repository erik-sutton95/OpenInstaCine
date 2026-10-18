package com.opencapture.openinstacine.monitor.pairing

import com.opencapture.opencine.platform.CameraWifiStorageConfiguration

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
