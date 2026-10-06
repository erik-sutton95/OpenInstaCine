import Foundation
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// LUT long-press body: Insta360 / Creative / Custom, then exposure and 50/50.
///
/// Auto follows color with the official Insta360 I-Log to Rec.709 cube. Creative is Mono /
/// Contrast / Warm / Cool. Custom is imported `.cube` files. The assist-bar
/// chip is off. Exposure is input-referred stops before the cube (ETTR pull).
enum LUTAssist {
    static let exposureTitle = "Exposure"
    static let exposureHelp = "Input stops before the cube. Pull 1–2 after ETTR."
    /// Live Photo / Photo is Rec.709; do not label a stale D-Log conversion.
    static let photoRec709Caption = "Photo live view is Rec.709 — log conversions are off"

    @ViewBuilder
    static func longPressMenu(assist: LiveAssistState) -> some View {
        LUTPicker(assist: assist, embedded: true)
    }

    @ViewBuilder
    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        LUTPicker(assist: assist, embedded: true)
    }

    /// Pinned under the catalog so landscape never scrolls exposure / 50/50 off-screen.
    @ViewBuilder
    static func longPressFooter(assist: LiveAssistState) -> some View {
        LUTSplitComparisonBar(assist: assist)
    }
}

/// Official Insta360 Luna I-Log to Rec.709 cube from the app bundle. Parsed once.
enum BundledLunaLUT {
    static let resourceName = "Luna_I-Log_to_Rec709_BT1886_s33_v2"
    private static let lock = NSLock()
    private static var cache: CubeLUT?

    static var iLogToRec709: CubeLUT? {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "cube"),
            let text = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? CubeLUT.parse(text)
        else { return nil }
        cache = parsed
        return parsed
    }
}

extension OfficialLUTs {
    /// The bundled I-Log cube. No Pocket or DJI cube ships with this app.
    static let app = OfficialLUTs { source in
        if case .iLogRec709 = source { return BundledLunaLUT.iLogToRec709 }
        return nil
    }
}

extension LUTPreferences {
    /// Saved LUT choices under this app's key names (`OpenInstaCine.LUTSelection` and so on).
    static let app = LUTPreferences(storage: .standard, namespace: "OpenInstaCine")
}

extension CustomLUTStore {
    /// Imported `.cube` files in Documents/luts/custom.
    static let app = CustomLUTStore(
        root: (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("luts/custom", isDirectory: true),
        preferences: .app)
}
