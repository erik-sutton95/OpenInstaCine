import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

enum StartupColors {
    static let background = MonitorTheme.background
    static let surface = MonitorTheme.surface
    static let tile = MonitorTheme.raised
    static let control = MonitorTheme.faint
    static let ink = MonitorTheme.text
    static let muted = MonitorTheme.muted
    static let dim = MonitorTheme.faint
    static let border = Color.white
    static let card = MonitorTheme.surface
    static let accent = MonitorTheme.accent
    static let ready = Color(red: 0.247, green: 0.710, blue: 0.416)
    static let destructive = MonitorTheme.recording
    static let darkText = MonitorTheme.canvas
    static var backdrop: some View { MonitorTheme.background }
}

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
    static var text: Color { LiveHDRDisplay.chromeColor(red: 1, green: 1, blue: 1) }
    static var muted: Color { LiveHDRDisplay.chromeColor(hex: 0x8D9293) }
    static var faint: Color { LiveHDRDisplay.chromeColor(hex: 0x5E6262) }
    static var accent: Color { LiveHDRDisplay.chromeColor(hex: MonitorTheme.accentRGB) }
    static let accentDim = MonitorTheme.accent.opacity(0.16)
    /// Ink for text/icons on a solid accent fill (dark on the light Luna yellow).
    static var onAccent: Color { MonitorTheme.onAccent }
    static var amber: Color { LiveHDRDisplay.chromeColor(red: 0.914, green: 0.674, blue: 0.208) }
    static var good: Color { LiveHDRDisplay.chromeColor(red: 0.18, green: 0.78, blue: 0.42) }
    /// AE lock yellow: the focus box, its `AE-L` tag and the unlock key.
    static var aeLock: Color { LiveHDRDisplay.chromeColor(hex: 0xF5D052) }
    static var rec: Color { LiveHDRDisplay.chromeColor(hex: 0xD13034) }
    static var info: Color { accent }
    static let cornerRadius = MonitorTheme.radius
    static let controlHeight: CGFloat = 58
}

/// The shared live chrome reads this app's palette.
extension LiveDesign: LiveChromePalette {
    static func chromeColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> Color {
        LiveHDRDisplay.chromeColor(red: red, green: green, blue: blue)
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

/// App copy around the shared pair page: the tips this app shows in the Luna pairing slot
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

struct StartupFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(MonitorTheme.font(16, weight: .semibold))
                .foregroundStyle(StartupColors.darkText)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    StartupColors.accent.opacity(configuration.isPressed ? 0.80 : 1),
                    in: RoundedRectangle(cornerRadius: MonitorTheme.radius)
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}
