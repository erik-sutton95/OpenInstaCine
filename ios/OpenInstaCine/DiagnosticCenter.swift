import Foundation
import class OpenCineCore.LocalVPNNotice
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenInstaViewCore

/// This app's on-device diagnostics: OpenCine's `DiagnosticCenterRuntime` with this app's
/// journal, redaction, incidents and Local Network status, read through its session.
final class DiagnosticCenter: DiagnosticCenterRuntime {
    static let shared = DiagnosticCenter()

    private init() {
        super.init(
            host: .init(
                product: "Field monitor", subsystem: "com.opencapture.openinstacine",
                journal: ControlLiveLog, redact: { PrivacyRedactor.redact($0) },
                isSafeNetwork: { _ in false }, incidents: { AppDiagnostics.incidents },
                localNetwork: { LocalNetworkAccess.status.rawValue },
                currentCamera: { AppModelDiagnosticsAnchor.session.map(Self.camera) }))
    }

    @MainActor static func camera(_ session: CameraSession) -> DiagnosticCamera {
        DiagnosticCamera(
            family: session.connectedCamera?.model.family, model: session.connectedCamera?.model.name,
            phase: session.phase)
    }

    @MainActor
    func manualReport(session: CameraSession) -> String {
        manualReport(camera: Self.camera(session))
    }

    @MainActor
    func writeReport(session: CameraSession) -> URL? {
        writeReport(camera: Self.camera(session))
    }

    /// Compact paste plus `report.txt` for the system share sheet.
    @MainActor
    func beginShare(session: CameraSession) -> ShareOutcome {
        beginShare(camera: Self.camera(session))
    }
}

/// Weak back-reference so screenshot handling can read the live session
/// without a DiagnosticCenter ↔ AppModel import cycle at init.
enum AppModelDiagnosticsAnchor {
    @MainActor static weak var model: AppModel?
    /// The live session, or nil before the app model exists. Never a stand-in session.
    @MainActor static var session: CameraSession? { model?.session }
}

extension LocalVPNNotice {
    /// This app's once-per-launch local VPN line in the diagnostics journal.
    static let app = LocalVPNNotice { message in
        DiagnosticCenter.shared.event(
            level: .notice, category: .session, code: "vpn", message: message)
    }
}
