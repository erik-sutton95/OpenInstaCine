import MonitorUI
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenInstaViewCore
import SwiftUI

enum LiveDesign {
    static let background = MonitorTheme.canvas
    static let surface = MonitorTheme.surface
    static let glass = MonitorTheme.surface
    static let glassOpaque = MonitorTheme.surface
    static let chromePlate = MonitorTheme.surface
    static let chromeTint = MonitorTheme.surface
    static let glassBright = MonitorTheme.raised
    static let hairline = MonitorTheme.border
    static let hairlineStrong = MonitorTheme.faint.opacity(0.5)
    static var text: Color { LiveHDRDisplay.app.chromeColor(red: 1, green: 1, blue: 1) }
    static var muted: Color { LiveHDRDisplay.app.chromeColor(hex: 0x8D9293) }
    static var faint: Color { LiveHDRDisplay.app.chromeColor(hex: 0x5E6262) }
    static var accent: Color { LiveHDRDisplay.app.chromeColor(hex: MonitorTheme.accentRGB) }
    static let accentDim = MonitorTheme.accent.opacity(0.16)
    /// Ink for text/icons on a solid accent fill (dark on the light Luna yellow).
    static var onAccent: Color { MonitorTheme.onAccent }
    static var amber: Color { LiveHDRDisplay.app.chromeColor(red: 0.914, green: 0.674, blue: 0.208) }
    static var good: Color { LiveHDRDisplay.app.chromeColor(red: 0.18, green: 0.78, blue: 0.42) }
    /// AE lock yellow: the focus box, its `AE-L` tag and the unlock key.
    static var aeLock: Color { LiveHDRDisplay.app.chromeColor(hex: 0xF5D052) }
    static var rec: Color { LiveHDRDisplay.app.chromeColor(hex: 0xD13034) }
    static var info: Color { accent }
    static let cornerRadius = MonitorTheme.radius
    static let controlHeight: CGFloat = 58
}

/// The shared live chrome reads this app's palette.
extension LiveDesign: LiveChromePalette {
    static var destructive: Color { StartupColors.destructive }

    static func chromeColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> Color {
        LiveHDRDisplay.app.chromeColor(red: red, green: green, blue: blue)
    }
}

typealias CloseButton = LiveCloseButton<LiveDesign>

extension View {
    /// Compositor-owned Field Monitor material; no application-side frame copy.
    func liveChromeGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        monitorGlass(in: shape)
            .environment(\.colorScheme, .dark)
    }
    func liveChromeCapsule(interactive: Bool = false) -> some View {
        liveChromeGlass(in: Capsule(), interactive: interactive)
    }
    func liveChromeCircle(interactive: Bool = false) -> some View {
        liveChromeGlass(in: Circle(), interactive: interactive)
    }
}

/// App copy around the pair wizard: the cards it shows while choosing a camera
/// (a running Insta360 app holds the camera; `preCheck` and `scanEmptyHint` match Android word
/// for word) and the Personal Hotspot join refusal.
enum StartupConnectionCopy {
    static let personalHotspotOn =
        "Turn off Personal Hotspot, then try again. While it is on, this iPhone cannot join the camera Wi-Fi."
    static let preCheckTitle = "Check first"
    static let preCheck = "Before pairing, force quit the Insta360 app."
    static let scanEmptyTitle = "Still looking"
    static let scanEmptyHint =
        "Force quit the Insta360 app on every phone near the camera. Make sure the camera is on and activated, then move closer."
}

