import Foundation
import MonitorCore

/// Pocket mapping onto OpenZCine's FPS chip labels + `CameraLinkHealthScorer` phase.
///
/// SoftAP HEVC live view is 1280×720 at ~25 fps (`docs/protocol-notes.md`). That is the
/// delivery target for bars — not `CameraStatus.fps`, which is the recording format already
/// shown on the Rec chip. There is no SoftAP RSSI on the bus (and iOS cannot read it).
public enum LiveViewLink {
    public static let targetFPS: Double = 25

    public static func cameraLinkPhase(
        connection: ConnectionPhase,
        recovering: Bool,
        measuredFPS: Double
    ) -> CameraLinkPhase {
        if case .failed = connection { return .disconnected }
        if measuredFPS > 0 { return recovering ? .recovering : .streaming }
        switch connection {
        case .idle: return .disconnected
        case .live: return .connectedIdle
        default: return .connecting
        }
    }

    public static func fpsChipLabel(
        connection: ConnectionPhase,
        recovering: Bool,
        formattedFPS: String,
        measuredFPS: Double
    ) -> String {
        if case .failed = connection { return "FAIL" }
        if recovering { return "RECOV" }
        if measuredFPS > 0 { return formattedFPS }
        switch connection {
        case .idle: return "—"
        default: return "LINK"
        }
    }
}
