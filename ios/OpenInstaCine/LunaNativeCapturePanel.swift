import Insta360Apple
import Insta360Protocol
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCore
import SwiftUI

/// Integration-owned values and actions are composed into the shared drawer.
struct LunaNativeCapturePanel: View {
    @Bindable var model: AppModel
    let sheet: CaptureSheet
    let enabled: Bool
    private struct Source: Hashable {
        let camera: UUID?
        let session: CameraSessionID?
        let epoch: ControlEpoch?
        let native: UUID?
    }
    private var source: Source {
        .init(camera: model.connectedCameraID, session: model.control.snapshot?.session,
            epoch: model.control.snapshot?.epoch, native: model.session.lunaSession?.commandOwner.source)
    }
    var body: some View {
        let captured = source
        let admitted = { enabled && source == captured && !model.sessionLocked && !model.coverOpen && model.control.isRecording == false && !model.operatorSession.locked }
        if sheet == .resolution {
            CaptureFormatPicker(choices: formatChoices, current: model.session.nativeRecordingFormat,
                enabled: admitted(), haptics: model.hapticsEnabled, sourceIdentity: AnyHashable(captured),
                followsReadback: model.session.nativeFormatPin == nil, isCurrent: admitted) { choice in
                    guard admitted() else { return }
                    model.session.setNativeRecordingFormat(choice.value)
                }
        } else {
            let choices = LunaColorMode.nativeRecordingChoices
            MonitorValueDrum(options: choices.map(\.label), selection: Binding(
                get: { model.session.nativeRecordingColor.flatMap { choices.contains($0) ? $0.label : nil } ?? "" },
                set: { label in
                    guard admitted(), let choice = choices.first(where: { $0.label == label }) else { return }
                    model.session.setNativeRecordingColor(choice)
                }), isInteractive: admitted(), haptics: model.hapticsEnabled,
                interactionIdentity: { AnyHashable(captured) })
        }
    }
    private var formatChoices: [CaptureFormatChoice<LunaVideoResolution>] {
        var values = LunaShellMapping.videoFormatValues.compactMap(LunaVideoResolution.init(rawValue:))
        if let current = model.session.nativeRecordingFormat, !values.contains(current) { values.insert(current, at: 0) }
        return values.map { value in
            let dimensions = CameraRecordingFormat.Dimensions(width: value.width, height: value.height)
            let format = CameraRecordingFormat(dimensions: dimensions, frameRate: Rational.frameRate(value.framesPerSecond))
            let label = dimensions.map(MonitorCapturePresentation.resolutionLabel) ?? "Unknown"
            return CaptureFormatChoice(value: value, title: MonitorCapturePresentation.recordingLabel(format) ?? "Unknown",
                aspect: .init(id: value.aspectLabel, title: value.aspectLabel),
                resolution: .init(id: "\(value.width)x\(value.height)", title: label),
                frameRate: format.frameRate.map { .init(id: $0.description, title: MonitorCapturePresentation.frameRate($0) + "p") },
                isEditable: LunaShellMapping.videoFormatValues.contains(value.rawValue))
        }
    }
}
