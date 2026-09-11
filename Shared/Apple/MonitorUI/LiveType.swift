import SwiftUI

/// Landing-page type (openpocketcine.app): Sora for titles, IBM Plex Sans for
/// body / help / chrome labels. Camera property readouts stay SF Mono via
/// `.font(.system(..., design: .monospaced))` and are not routed through here.
enum LiveType {
    /// Sora — display face used for the site wordmark, h1, and h2.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.custom(soraName(weight), size: size)
    }

    /// IBM Plex Sans — site body face for help, settings, buttons, and labels.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(plexName(weight), size: size)
    }

    /// Map a former `.system` UI face onto the landing families.
    ///
    /// - Monospaced stays SF Mono (ISO, shutter, timecode, FPS, scopes).
    /// - Rounded titles and large semibold/bold copy become Sora.
    /// - Everything else becomes IBM Plex Sans.
    static func ui(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        if design == .monospaced {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        if design == .rounded {
            if isTitleWeight(weight) || size >= 16 {
                return display(size, weight: weight)
            }
            return text(size, weight: weight)
        }
        if isTitleWeight(weight) && size >= 17 {
            return display(size, weight: weight)
        }
        return text(size, weight: weight)
    }

    /// PostScript names of the bundled faces — used by tests after `UIAppFonts` load.
    static let bundledPostScriptNames = [
        "Sora-Medium", "Sora-SemiBold", "Sora-Bold",
        "IBMPlexSans-Regular", "IBMPlexSans-Medium", "IBMPlexSans-SemiBold", "IBMPlexSans-Bold",
    ]

    private static func isTitleWeight(_ weight: Font.Weight) -> Bool {
        weight == .semibold || weight == .bold || weight == .heavy || weight == .black
    }

    private static func soraName(_ weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return "Sora-Bold" }
        if weight == .medium { return "Sora-Medium" }
        if weight == .regular || weight == .light || weight == .thin || weight == .ultraLight {
            return "Sora-Medium"
        }
        return "Sora-SemiBold"
    }

    private static func plexName(_ weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return "IBMPlexSans-Bold" }
        if weight == .semibold { return "IBMPlexSans-SemiBold" }
        if weight == .medium { return "IBMPlexSans-Medium" }
        return "IBMPlexSans-Regular"
    }
}
