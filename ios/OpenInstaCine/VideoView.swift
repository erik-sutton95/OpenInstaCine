import OpenCineAppKitApple
import OpenCineApple
import OpenCineCameraControls

/// This app's typed values for the shared live picture (OpenCineAppKitApple).
enum InstaLivePicture: MonitorLivePictureApp {
    typealias Decoder = HevcDecoder
    static var hdrDisplay: LiveHDRDisplay { .app }
    static var feedUpscaler: MonitorUpscalerPreference { FeedUpscaleSwitch.shared }
    static var logSubsystem: String { "com.opencapture.openinstacine" }
    static var presentObserver: (() -> Void)? {
        #if DEBUG
            { FeedStressAutomation.noteMetalPresent() }
        #else
            nil
        #endif
    }
}

extension HevcDecoder: MonitorLiveVideoSource {
    /// The sample bus is this decoder's whole source publication.
    func bindSourcePublication(_ bus: LiveFrameSampleBus) {
        sampleBus = bus
    }
}

typealias VideoView = MonitorLiveVideoView<InstaLivePicture>
typealias VideoDisplayRepresentable = MonitorLiveVideoRepresentable<InstaLivePicture>
typealias DisplayLayerView = MonitorLiveDisplayLayerView<InstaLivePicture>
typealias CIFeedView = MonitorLiveFeedView<InstaLivePicture>
