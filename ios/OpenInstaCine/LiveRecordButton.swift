import MonitorUI
import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI

/// A confirmation authorizes the capture state visible when it was opened. Its target is
/// explicit (start when the camera reported idle, stop when it reported recording); unknown
/// recording cannot be confirmed.
struct RecordConfirmationContext: Equatable {
    let mode: Int
    /// Camera-reported recording; nil while unknown.
    let recording: Bool?
    let locked: Bool
    let busy: Bool
    let phase: ConnectionPhase

    var canConfirm: Bool {
        recording != nil && !locked && !busy && phase == .live
            && ShootingMode.fromStatus(mode)?.isPhoto != true
    }
}

/// Integration adapter: the shared control owns video capture and confirmation.
struct LiveRecordButton: View {
    var diameter: CGFloat = LiveChromeMetrics.recordButtonSize
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var locked

    var body: some View {
        MonitorCaptureButton(
            control: model.control, diameter: diameter,
            enabled: !locked && !model.session.isLocked && !model.session.controlBusy
                && model.session.phase == .live,
            photo: model.session.status.isPhoto,
            confirm: model.recordConfirmationEnabled, haptics: model.hapticsEnabled,
            takePhoto: { model.session.pressShutter() },
            openMode: { model.captureSheet = .mode })
    }
}

/// Osmo Pocket shutter: recessed charcoal well, thin coral ring. Recording fills the ring.
struct RecordLamp: View {
    let diameter: CGFloat
    let recording: Bool
    var body: some View { MonitorRecordLamp(diameter: diameter, recording: recording) }
}
