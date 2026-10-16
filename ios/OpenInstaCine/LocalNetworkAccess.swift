import OpenCineApple
import OpenCineCore
import OpenInstaViewCore

/// iOS Local Network privacy (TN3179) through the shared observer. The Luna camera link reports
/// its explicit policy denial and a completed control handshake; no extra probe or prompt runs.
@MainActor
enum LocalNetworkAccess {
    /// The app's one observer: the permission belongs to the app, not to a camera session.
    static let privacy = LocalNetworkPrivacy { state, source in
        ControlLiveLog.line("localNetwork: \(state.rawValue) (\(source))")
    }

    static var status: CameraNetworkPermissionState { privacy.state }
}
