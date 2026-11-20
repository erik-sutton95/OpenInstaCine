import Insta360Apple
import OpenCineAppKitApple
import OpenCineCore
import OpenCineStreaming

/// Live streaming's host values: the keychain service, the route the connected camera took, the
/// live feed's shape and the clean picture tap on the live decoder. Nothing here sends a camera
/// command.
extension AppModel {
    func makeLiveStream() -> LiveStreamCoordinator {
        LiveStreamCoordinator(host: LiveStreamHost(
            keychainService: "com.opencapture.openinstacine.live-stream",
            route: { [weak self] in self?.liveStreamRoute },
            source: { [weak self] in self?.liveStreamSource },
            attachPicture: { [weak self] in self?.session.decoder.setCleanPictureTap($0) },
            // No permission gate of its own: the plain system request, after Go live is confirmed.
            microphoneAccess: LiveStreamHost.systemMicrophoneAccess))
    }

    /// The route only while this phone's own camera shows a live picture: the camera's Wi-Fi blocks
    /// streaming; station mode on a shared network or this phone's hotspot allows it.
    var liveStreamRoute: StreamConnectionRoute? {
        guard session.phase == .live, !isWatchingFeed, let camera = session.connectedCamera else { return nil }
        switch session.backend.reconnectRoute(for: camera.id) {
        case .cameraWiFi: return .cameraWiFi
        case .station(let network): return network.hotspot ? .deviceHotspot : .sharedWiFi
        }
    }

    /// The preview feed is 1280x720 HEVC at 25 fps (upright when the camera is turned).
    var liveStreamSource: StreamSourceFormat? {
        guard session.phase == .live else { return nil }
        let rate = Rational(25, 1)
        return session.isVerticalPicture
            ? StreamSourceFormat(width: 720, height: 1280, frameRate: rate)
            : StreamSourceFormat(width: 1280, height: 720, frameRate: rate)
    }
}
