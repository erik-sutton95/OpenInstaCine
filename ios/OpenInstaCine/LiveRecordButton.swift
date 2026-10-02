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

/// REC tally on the physical screen bezel \u{2014} OpenZCine `RecordingBorderModule`.
struct LiveRecordingTally: View {
    var cornerRadius: CGFloat = LiveRecordingTally.displayCornerRadius
    @Environment(\.monitorPresentationIsVisible) private var isVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Core Animation owns the pulse: the render server animates opacity with
        // no per-step app or SwiftUI work for the whole take (a SwiftUI timeline
        // here cost about a third of the app's CPU while recording).
        LiveRecordingTallyLayer(
            cornerRadius: cornerRadius, color: UIColor(LiveDesign.rec),
            pulsing: isVisible && scenePhase == .active && !reduceMotion
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static let lineWidth: CGFloat = 4
    /// Approximate display corner. No public API; decorative, tuned to modern iPhones.
    static let displayCornerRadius: CGFloat = 52
}

/// Full-screen REC border: stroke plus glow on a precomputed shadow path, with a
/// render-server opacity pulse (same period and floor as `monitorPulse`).
private struct LiveRecordingTallyLayer: UIViewRepresentable {
    let cornerRadius: CGFloat
    let color: UIColor
    let pulsing: Bool

    func makeUIView(context: Context) -> TallyView { TallyView() }

    func updateUIView(_ view: TallyView, context: Context) {
        view.configure(cornerRadius: cornerRadius, color: color, pulsing: pulsing)
    }

    final class TallyView: UIView {
        private let border = CAShapeLayer()
        private var cornerRadius: CGFloat = 0
        private var pulsing = false
        private static let pulseKey = "rec-pulse"

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            border.fillColor = nil
            border.lineWidth = LiveRecordingTally.lineWidth
            border.shadowOpacity = 0.55
            border.shadowRadius = 14
            border.shadowOffset = .zero
            layer.addSublayer(border)
        }

        required init?(coder: NSCoder) { nil }

        func configure(cornerRadius: CGFloat, color: UIColor, pulsing: Bool) {
            self.cornerRadius = cornerRadius
            border.strokeColor = color.cgColor
            border.shadowColor = color.cgColor
            self.pulsing = pulsing
            applyPulse()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            border.frame = bounds
            // strokeBorder: the stroke sits inside the bounds.
            let inset = LiveRecordingTally.lineWidth / 2
            let path = UIBezierPath(
                roundedRect: bounds.insetBy(dx: inset, dy: inset),
                cornerRadius: max(0, cornerRadius - inset)
            ).cgPath
            border.path = path
            border.shadowPath = path.copy(
                strokingWithWidth: LiveRecordingTally.lineWidth, lineCap: .butt,
                lineJoin: .miter, miterLimit: 10)
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Core Animation drops animations when a layer leaves the window.
            applyPulse()
        }

        private func applyPulse() {
            let active = pulsing && window != nil
            guard active != (border.animation(forKey: Self.pulseKey) != nil) else { return }
            guard active else {
                border.removeAnimation(forKey: Self.pulseKey)
                return
            }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = MonitorMotion.recPulseFloor
            pulse.duration = MonitorMotion.recPulseDuration / 2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            pulse.isRemovedOnCompletion = false
            border.add(pulse, forKey: Self.pulseKey)
        }
    }
}
