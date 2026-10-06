import OpenCineAppKitApple
import OpenCineApple
import UIKit

// Source calibration, display preference and diagnostics remain app inputs.

final class PlaybackFeedSession: OpenCineApple.MonitorPlaybackFeedSession, @unchecked Sendable {
    @MainActor init() {
        super.init(configuration: LiveAssistEngine.configuration,
            hdrDisplay: { LiveHDRDisplay.app.isEnabled }, journal: { ControlLiveLog.line($0) },
            sourceAdvanced: {
                NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
            })
    }
}

final class PlaybackFeedHostView: OpenCineApple.MonitorPlaybackFeedHost {
    init(frame: CGRect = .zero) {
        super.init(frame: frame, picture: CIFeedView(), configurePlayerLayer: { LiveHDRDisplay.app.configure($0) })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
