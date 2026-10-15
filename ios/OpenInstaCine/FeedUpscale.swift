import Foundation
import OpenCineApple
import Metal
import Observation
import os

#if canImport(MetalFX)
    import MetalFX
#endif
#if !targetEnvironment(simulator)
    import VideoToolbox
#endif

/// Persisted feed-upscaler choice. The renderer reads `rendererReadsUpscaler` off the main actor.
@MainActor
@Observable
final class FeedUpscaleSwitch {
    static let shared = FeedUpscaleSwitch()

    private nonisolated static let storageKey = "OpenInstaCine.feedUpscaler"

    var upscaler: MonitorUpscaler = FeedUpscaleSwitch.rendererReadsUpscaler {
        didSet {
            Self.rendererReadsUpscaler = upscaler
            UserDefaults.standard.set(upscaler.rawValue, forKey: Self.storageKey)
            AppDiagnostics.reporting.noteFeedUpscaler(upscaler.rawValue)
        }
    }

    private nonisolated static let rendererSelection = OSAllocatedUnfairLock(
        initialState: MonitorUpscaler.supported(or: storedChoice))
    private nonisolated static let rendererInputPreview = OSAllocatedUnfairLock(initialState: false)

    nonisolated static var rendererReadsUpscaler: MonitorUpscaler {
        get { rendererSelection.withLock { $0 } }
        set { rendererSelection.withLock { $0 = newValue } }
    }

    nonisolated static var presentsSuperResolutionInput: Bool {
        get { rendererInputPreview.withLock { $0 } }
        set { rendererInputPreview.withLock { $0 = newValue } }
    }

    private nonisolated static var storedChoice: MonitorUpscaler? {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        if let known = MonitorUpscaler(rawValue: stored) { return known }
        switch stored {
        case "Lanczos": return .lanczos
        case "MetalFX": return .spatial
        case "Super Res": return .superResolution
        default: return nil
        }
    }

    private init() {}

    func toggleAgainstOff() {
        if upscaler == .off {
            upscaler = .supported(or: restoreAfterOff)
            restoreAfterOff = nil
        } else {
            restoreAfterOff = upscaler
            upscaler = .off
        }
    }

    @ObservationIgnored private var restoreAfterOff: MonitorUpscaler?
}
