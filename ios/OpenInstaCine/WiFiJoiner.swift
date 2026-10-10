import NetworkExtension

/// Removes the hotspot configuration iOS keeps for a camera SoftAP.
enum WiFiJoiner {
    static func leave(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }
}
