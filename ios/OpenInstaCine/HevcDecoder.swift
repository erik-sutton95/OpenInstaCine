import Foundation
import OpenCineApple
import OpenCineCameraControls
import OpenCineMedia
import OpenInstaViewCore

/// Camera interpretation and host values for the shared native decoder.
@MainActor
final class HevcDecoder: OpenCineApple.MonitorLiveVideoDecoder {
    var incomingColorMode: ColorMode? {
        didSet {
            if let incomingColorMode { incomingTransfer = MonitorTransfer(incomingColorMode) }
        }
    }

    init(assistConfiguration: OpenCineApple.MonitorAssistConfiguration = LiveAssistEngine.configuration) {
        super.init(configuration: .init(
            assists: assistConfiguration,
            shouldRebuildSession: { CameraSoftAP.shouldRebuildVTSession(status: $0) },
            // Incident policy observations are sampled by the owned CameraSession. This callback
            // has no captured source token and must not submit to a current global incident sink.
            decodeEvent: { event in
                #if DEBUG
                switch event {
                case .submitted: FeedStressAutomation.noteDecodeSubmit()
                case .decoded: FeedStressAutomation.noteDecoded()
                case .presented: FeedStressAutomation.notePresent()
                }
                #endif
            },
            discardOutput: {
                #if DEBUG
                return FeedStressAutomation.shouldSilenceOutput()
                #else
                return false
                #endif
            }), simulator: SimulatorLiveFeed.configuration)
        feedUpscaler = FeedUpscaleSwitch.shared.upscaler
        onSourceAdvanced = {
            NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
        }
    }

    override func startSimulatorSampleIfNeeded() {
        #if targetEnvironment(simulator)
            guard SimulatorLiveFeed.isConfigured else { return }
        #endif
        super.startSimulatorSampleIfNeeded()
    }
}

/// The app keeps its existing operator-selected footage namespace and source interpretation.
enum SimulatorLiveFeed {
    static var clipURL: URL? {
        let env = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"]
        let stored = UserDefaults.standard.string(forKey: "OPV.SimFeedClipPath")
        guard let path = [env, stored].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    static var isConfigured: Bool {
        clipURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static var configuration: MonitorSimulatorVideoConfiguration {
        .init(clipURL: { Self.clipURL }, transfer: .dlog2, queueLabel: "opv.sim-live",
            logSubsystem: "com.opencapture.openinstacine",
            missingClipMessage: "Simulator live feed clip not configured - set OPV_SIM_FEED_CLIP or OPV.SimFeedClipPath",
            startedMessage: "Simulator D-Log2 clip looping through handleDecodedFrame")
    }
}
