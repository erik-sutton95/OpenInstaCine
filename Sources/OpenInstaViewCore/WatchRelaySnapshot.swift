import Foundation
import OpenCineCore
import OpenCineRelay

/// This app's side of the shared watch relay (OpenCineRelay): the wrist copy that names the
/// app, and the snapshot from this app's camera status.
extension WatchRelayCopy {
    public static let openOnIPhone = "Open the app on iPhone"
}

extension WatchRelayState {
    /// Typed power reaches the wrist without reinterpreting a camera scalar.
    public static func snapshot(status: CameraStatus, timecode: String, phase: ConnectionPhase,
        cameraName: String, feedLive: Bool, power: PowerStatus) -> WatchRelayState {
        let legacy = snapshot(status: status, timecode: timecode, phase: phase,
            cameraName: cameraName, feedLive: feedLive)
        return WatchRelayState(isRecording: legacy.isRecording, timecode: legacy.timecode,
            media: legacy.media, cameraBatteryPercent: legacy.cameraBatteryPercent,
            cameraName: legacy.cameraName, connection: legacy.connection, feedLive: legacy.feedLive,
            isPhotography: legacy.isPhotography, feedAspectRatio: legacy.feedAspectRatio,
            batteryReading: power.batteryReading, batteryExhausted: power.exhausted.value)
    }

    /// Snapshot from live telemetry. `feedLive` is whether a picture has presented. `timecode` is
    /// the clock as the shared status shows it (`MonitorStatusPresentation.clock`).
    public static func snapshot(
        status: CameraStatus,
        timecode: String,
        phase: ConnectionPhase,
        cameraName: String,
        feedLive: Bool
    ) -> WatchRelayState {
        let live = {
            if case .live = phase { return true }
            return false
        }()
        let photography = status.isPhoto
        return WatchRelayState(
            isRecording: status.isRecording,
            timecode: timecode,
            media: WatchRelayMedia.label(
                storageFreeMb: status.storageFreeMb,
                storageTotalMb: status.storageTotalMb,
                sdFreeMb: status.sdFreeMb,
                sdTotalMb: status.sdTotalMb,
                recordRemainingSec: status.recordRemainingSec),
            cameraBatteryPercent: status.batteryPercent,
            cameraName: cameraName,
            connection: live ? .connected : .noCamera,
            feedLive: live && feedLive,
            isPhotography: photography,
            feedAspectRatio: 16.0 / 9.0)
    }
}
