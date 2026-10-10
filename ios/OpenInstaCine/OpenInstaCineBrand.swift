import MonitorUI
import OpenInstaViewCore

/// Storefront identity for the shared monitor engine. Applied once at launch,
/// before any view is built.
enum OpenInstaCineBrand {
    /// Insta360-adjacent yellow, not the OEM chip colour.
    static let accentRGB: UInt32 = 0xFFCF00

    @MainActor static func apply() {
        MonitorTheme.accentRGB = accentRGB
        // Camera labels, media route and zoom ceiling are per session (`LunaShellMapping.profile`).
        #if DEBUG
            DebugRemote.start()
        #endif
    }
}
