import Foundation
import MonitorCore

/// Osmo status/profile translations; no wire enums enter MonitorCore.
extension MonitorTransfer {
    public init(_ colorMode: ColorMode) {
        switch colorMode {
        case .normal, .normal10: self = .rec709
        case .hdr: self = .hdr
        case .dLog, .dLogM: self = .dlog
        case .dLog2: self = .dlog2
        }
    }

    /// Fingerprint the live tap when ColorMode `@2` has not arrived.
    ///
    /// D-Log2 paper black is byte 16 and the ISO 1600 preview ceiling is ~247.
    /// Plotting those codes on Rec.709 WAVE is the screenshot shelf (black at
    /// ~8, ceiling at ~75). An explicit ColorMode (`fallback` other than
    /// Rec.709) always wins.
    public static func inferred(
        minByte: UInt8, maxByte: UInt8, fallback: MonitorTransfer
    ) -> MonitorTransfer {
        guard fallback == .rec709 else { return fallback }
        // Expanded D-Log2: paper black 16, live-tap ceiling 247 (also 243–246).
        if (12...22).contains(minByte), (180...252).contains(maxByte) { return .dlog2 }
        // Expanded D-Log: paper black ~24, live-tap ceiling 223 (219–223).
        if (20...30).contains(minByte), (160...240).contains(maxByte) { return .dlog }
        return fallback
    }
}
