import OpenCineApple
import OpenCineCore
import OpenCineRelay
import OpenInstaViewCore

/// iOS Local Network privacy (TN3179) through the shared observer. The Luna camera link reports
/// its explicit policy denial and a completed control handshake. A connect raises the system
/// prompt first, so it is answered before the camera link starts (hardware pass 8.0); a denial
/// the link named while the prompt was up is re-checked when the app becomes active (shell).
@MainActor
enum LocalNetworkAccess {
    /// The app's one observer: the permission belongs to the app, not to a camera session.
    static let privacy = LocalNetworkPrivacy { state, source in
        ControlLiveLog.line("localNetwork: \(state.rawValue) (\(source))")
    }

    static var status: CameraNetworkPermissionState { privacy.state }

    /// Browses our own relay type (Info.plist `NSBonjourServices`) while Bluetooth approves, so
    /// the prompt comes before the camera Wi-Fi join instead of during the control link.
    static func requestBeforeCameraJoin() {
        privacy.requestBeforeCameraJoin(serviceType: WatcherRelayProtocol.serviceType)
    }
}
