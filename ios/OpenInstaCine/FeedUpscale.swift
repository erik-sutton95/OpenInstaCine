import OpenCineApple

/// The app's feed-upscaler choice: the shared OpenCine preference under this app's key.
enum FeedUpscaleSwitch {
    static let shared = MonitorUpscalerPreference(
        storageKey: "OpenInstaCine.feedUpscaler",
        onChange: { AppDiagnostics.reporting.noteFeedUpscaler($0.rawValue) })
}
