import Foundation
import OpenCineCore
import OpenPocketViewCore

/// What one learned offset assumes: one camera, one recording profile and transfer, one
/// metering mode. A change of any of them reads (and learns) a different offset.
struct PictureEVContext: Hashable {
    var device: String
    var transfer: MonitorTransfer
    var profile: String
    var metering: String

    var key: String { "\(device)|\(transfer.rawValue)|\(profile)|\(metering)" }
}

/// EV meter for a camera that reports no metered EV: the picture's median against 18%
/// grey, less where the camera's own auto exposure places it. With matrix metering the
/// Luna puts the I-Log median about 1.3 stops under 18% grey at EV 0 (2026-09-30). While
/// the camera exposes in auto that offset is learned (median stops minus EV comp) and kept
/// per `PictureEVContext`, so in manual the meter reads how far the exposure is from where
/// auto would put it. The result is image-estimated; a camera-reported EV always wins.
///
/// One instance per source (`CameraSession.pictureEV`). Storage is shared: v2 is keyed by
/// context and each instance saves only its own keys. v1 (one offset per transfer for every
/// camera) is never written or removed; it seeds a v2 key of the same transfer that has no
/// value yet, so the migration is a read and running it again changes nothing.
@MainActor
final class PictureEVMeter {
    /// Time for the learned offset to follow a new scene (first order).
    static let learnSeconds = 3.0
    private static let seeds: [MonitorTransfer: Double] = [.ilog: -1.3]
    /// v1: `[transfer: offset]`, read only.
    static let legacyDefaultsKey = "OpenInstaCine.PictureEVMeter.offsets.v1"
    /// v2: `[PictureEVContext.key: offset]`.
    static let defaultsKey = "OpenInstaCine.PictureEVMeter.offsets.v2"

    private let defaults: UserDefaults
    /// This source's offsets, read or learned.
    private var offsets: [String: Double] = [:]
    private var learnedKeys: Set<String> = []
    private var lastContext: PictureEVContext?
    private var lastAt: TimeInterval?
    private var savedAt: TimeInterval = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func offset(for context: PictureEVContext) -> Double {
        if let known = offsets[context.key] { return known }
        let value =
            (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double])?[context.key]
            ?? (defaults.dictionary(forKey: Self.legacyDefaultsKey) as? [String: Double])?[
                context.transfer.rawValue]
            ?? Self.seeds[context.transfer] ?? 0
        offsets[context.key] = value
        return value
    }

    /// Estimated EV in stops. `evComp` is the camera's compensation while it exposes in auto,
    /// nil in manual.
    func stops(
        picture: Double, context: PictureEVContext, evComp: Double?, now: TimeInterval
    ) -> ObservedValue<Double> {
        // New assumptions start a new learning clock.
        if context != lastContext {
            lastContext = context
            lastAt = nil
        }
        var offset = offset(for: context)
        if let evComp {
            let dt = lastAt.map { min(max(now - $0, 0), 0.5) } ?? 0
            offset += (picture - evComp - offset) * (1 - exp(-dt / Self.learnSeconds))
            offsets[context.key] = offset
            learnedKeys.insert(context.key)
            if now - savedAt > 5 {
                savedAt = now
                save()
            }
        }
        lastAt = now
        // `now` is the learning clock only; the observation is stamped on the shared host clock.
        return ObservedValue(picture - offset, origin: .imageEstimated, at: .now())
    }

    /// Writes this source's learned keys over the stored v2 values; other keys stay as stored.
    func save() {
        var stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        for key in learnedKeys { stored[key] = offsets[key] }
        defaults.set(stored, forKey: Self.defaultsKey)
    }
}
