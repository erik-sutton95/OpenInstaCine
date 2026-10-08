import Foundation
import OpenCineApple
import OpenCineCore

extension CameraSession {
    /// Reads the subscribed camera snapshot, never pending targets or presentation defaults.
    var nativeQualificationSnapshot: MonitorNativeQualificationSnapshot {
        #if targetEnvironment(simulator)
        let simulated = true
        #else
        let simulated = false
        #endif
        let source = decoder.sourceToken
        let reported = control.snapshot
        let recording: Bool?
        switch reported?.recording.value {
        case .recording?: recording = true
        case .idle?: recording = false
        default: recording = nil
        }
        let iso: Int?
        let isoIsAuto: Bool?
        switch reported?.settings[.iso]?.value {
        case .iso(.manual(let value))?: iso = value; isoIsAuto = false
        case .iso(.auto)?, .iso(.autoLimited)?: iso = nil; isoIsAuto = true
        default: iso = nil; isoIsAuto = nil
        }
        return MonitorNativeQualificationSnapshot(
            simulated: simulated, sourceIdentity: source.map { String(describing: $0) },
            sourceActive: source.map { decoder.sourceToken == $0 },
            sourceFrameAt: decoder.lastSourceFrameAt?.timeIntervalSince1970,
            sourcePresentations: decoder.sourcePresentations,
            nativeDecodeOutputs: decoder.nativeOutputExpected ? decoder.nativeDecodeTotals.output : nil,
            cameraRecording: recording, cameraISO: iso, cameraISOIsAuto: isoIsAuto)
    }
}
