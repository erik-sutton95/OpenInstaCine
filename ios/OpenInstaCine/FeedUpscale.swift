import OpenCineApple

/// The app's feed-upscaler choice: the shared OpenCine preference under this app's key.
enum FeedUpscaleSwitch {
    static let shared = MonitorUpscalerPreference(
        storageKey: "OpenInstaCine.feedUpscaler",
        onChange: { AppDiagnostics.reporting.noteFeedUpscaler($0.rawValue) })
}

extension SettingsHelpCopy {
    static let feedUpscaler =
        "How the live-view frame is enlarged to fill the panel. The camera sends far fewer pixels than the panel has, so something always does this. Off is a plain sample, Fast is a fixed sharpening kernel, and Quality is the OS spatial upscaler.\n\nAI is different in kind: it is a machine-learning model that INFERS detail the camera never captured. It gives the sharpest-looking picture, but the fine texture it adds is invented — plausible rather than real — so it can suggest crispness the lens did not record. Judge critical focus on Quality or Fast, and treat AI as a viewing aid rather than evidence.\n\nOnly the options this device supports are shown."
}
