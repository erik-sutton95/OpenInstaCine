import CoreImage
import CoreVideo
import Foundation
import Observation
import OpenPocketViewCore
import OpenCineMedia
import OpenCineApple
import os

extension MonitorTransfer {
    /// Wire ColorMode that selected this transfer (`3F` / `3C` / `17` / `41`).
    var colorMode: ColorMode {
        switch self {
        case .rec709: .normal
        case .hdr: .hdr
        case .dlog: .dLog
        case .dlogm: .dLogM
        case .dlog2: .dLog2
        case .ilog: .iLog
        }
    }

    /// `CameraStatus.monitorTransfer`, else ColorMode, else the last known
    /// curve. Rec.709 only when nothing has been seen yet — falling back on a
    /// missing `@2` is the WAVE black shelf (D-Log2 paper black at ~8 IRE).
    static func resolved(
        _ status: MonitorTransfer?, colorMode: ColorMode?, previous: MonitorTransfer? = nil
    ) -> MonitorTransfer {
        status ?? colorMode.map(MonitorTransfer.init) ?? previous ?? .rec709
    }
}

// Source adapters select measured calibration and interpretation for the shared native owner.
extension ScopeSampler {
    static func minInterval(activeScopeCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> CFAbsoluteTime {
        OpenCineApple.MonitorAssistEngine.minInterval(activeScopeCount: activeScopeCount,
            thermalState: thermalState)
    }
    static func thermalMultiplier(_ state: ProcessInfo.ThermalState) -> Double {
        OpenCineApple.MonitorAssistEngine.thermalMultiplier(state)
    }
    static func copyBGRA(_ buffer: CVPixelBuffer, maxWidth: Int) ->
        (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        LiveFrameTap.copyBGRA8(buffer, maxWidth: maxWidth)
    }

}

typealias ScopeExposureCeiling = OpenPocketViewCore.ScopeExposureCeiling

extension LiveFrameSampleBus {
    var colorMode: ColorMode? { reportedTransfer.map(\.colorMode) }

}

/// Source adaptation supplies measured saturation, look tables and transfer inference.
final class LiveAssistEngine: @unchecked Sendable {
    typealias Result = OpenCineApple.MonitorAssistEngine.Result
    private let native: OpenCineApple.MonitorAssistEngine
    static var configuration: OpenCineApple.MonitorAssistConfiguration {
        let curves = Dictionary(uniqueKeysWithValues: [MonitorTransfer.rec709, .hdr, .dlog, .dlogm, .dlog2, .ilog].compactMap { transfer in
            LiveColorScience.rec709LookCurve(transfer).map { (transfer, $0) }
        })
        return .init(
            clipProfile: ScopeExposureCeiling.sourceProfile, lookCurves: curves,
            defaultScopeLook: { $0 == .ilog ? BundledLunaLUT.iLogToRec709 : nil },
            inferTransfer: { MonitorTransfer.inferred(minByte: $0, maxByte: $1, fallback: $2) },
            logSubsystem: "com.opencapture.openinstacine", journal: { ControlLiveLog.line($0) })
    }
    init() { native = OpenCineApple.MonitorAssistEngine(configuration: Self.configuration) }
    func adopt(exposureCeiling: OpenCineMedia.ScopeExposureCeiling) {
        native.adopt(exposureCeiling: exposureCeiling)
    }
    func updatePolicy(effects: LiveImageEffects, transfer: MonitorTransfer) {
        native.updatePolicy(effects: effects.nativeAssistPolicy, transfer: transfer)
    }
    func submit(_ buffer: CVPixelBuffer, effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil, timeNs: Int64 = 0,
        completion: @escaping @Sendable (Result) -> Void) {
        native.submit(buffer, effects: effects?.nativeAssistPolicy, transfer: transfer,
            timeNs: timeNs == 0 ? nil : timeNs, completion: completion)
    }
    func reset() { native.reset() }
}
extension OpenCineApple.MonitorAssistEngine.Result {
    var colorMode: ColorMode { transfer.colorMode }
}
