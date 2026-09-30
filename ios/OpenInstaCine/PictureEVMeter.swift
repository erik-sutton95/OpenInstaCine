import Foundation
import OpenPocketViewCore

/// EV meter for a camera that reports no metered EV: the picture's median against 18%
/// grey, less where the camera's own auto exposure places it. With matrix metering the
/// Luna puts the I-Log median about 1.3 stops under 18% grey at EV 0 (2026-09-30). While
/// the camera exposes in auto that offset is learned (median stops minus EV comp) and kept
/// per curve, so in manual the meter reads how far the exposure is from where auto would
/// put it, like a camera's own metered EV.
@MainActor
final class PictureEVMeter {
    static let shared = PictureEVMeter()
    /// Time for the learned offset to follow a new scene (first order).
    static let learnSeconds = 3.0
    private static let seeds: [MonitorTransfer: Double] = [.ilog: -1.3]
    private static let defaultsKey = "OpenInstaCine.PictureEVMeter.offsets.v1"

    private let defaults: UserDefaults
    private var offsets: [String: Double]
    private var lastAt: TimeInterval?
    private var savedAt: TimeInterval = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        offsets = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
    }

    func offset(for transfer: MonitorTransfer) -> Double {
        offsets[transfer.rawValue] ?? Self.seeds[transfer] ?? 0
    }

    /// Metered EV in stops. `evComp` is the camera's compensation while it exposes in auto,
    /// nil in manual.
    func stops(picture: Double, transfer: MonitorTransfer, evComp: Double?, now: TimeInterval) -> Double {
        var offset = offset(for: transfer)
        if let evComp {
            let dt = lastAt.map { min(max(now - $0, 0), 0.5) } ?? 0
            offset += (picture - evComp - offset) * (1 - exp(-dt / Self.learnSeconds))
            offsets[transfer.rawValue] = offset
            if now - savedAt > 5 {
                savedAt = now
                defaults.set(offsets, forKey: Self.defaultsKey)
            }
        }
        lastAt = now
        return picture - offset
    }
}
