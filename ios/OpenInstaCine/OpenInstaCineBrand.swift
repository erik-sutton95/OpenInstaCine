import MonitorUI
import OpenPocketViewCore

/// Storefront identity for the shared monitor engine. Applied once at launch,
/// before any view is built.
enum OpenInstaCineBrand {
    /// Insta360-adjacent yellow, not the OEM chip colour.
    static let accentRGB: UInt32 = 0xFFCF00

    @MainActor static func apply() {
        MonitorTheme.accentRGB = accentRGB
        // Luna serves every file at its own path on 192.168.42.1.
        MediaHTTP.addressing = .directPath
        MediaHTTP.host = "192.168.42.1"
        ShootingMode.labelOverrides = LunaShellMapping.shootingModeLabels
        #if DEBUG
            DebugRemote.start()
        #endif
    }
}
